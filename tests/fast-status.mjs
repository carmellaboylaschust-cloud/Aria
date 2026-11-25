import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtemp, rm, writeFile} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const port = 18245;
const base = `ws://127.0.0.1:${port}/devtools/`;
const theme = 'fixture-theme';

if (process.argv[2] === '--fixture') {
  const [, , , scenario, stateFile, budget] = process.argv;
  const page = (id, fields = {}) => ({type:'page', url:'app://fixture', webSocketDebuggerUrl:base+'page/'+id, ...fields});
  globalThis.fetch = async url => {
    if (url === `http://127.0.0.1:${port}/json/version`) {
      return {json:() => ({webSocketDebuggerUrl:base+'browser/'+(scenario === 'changed' ? 'other' : 'fixture')})};
    }
    assert.equal(url, `http://127.0.0.1:${port}/json/list`);
    const targets = [page('good'), page('wrong-host', {webSocketDebuggerUrl:'ws://example.invalid/page/other'}),
      page('other-page', {url:'https://example.invalid/'})];
    if (scenario === 'multiple') targets.unshift(page('closed'));
    return {json:() => targets};
  };
  globalThis.WebSocket = class {
    static OPEN = 1;
    readyState = 0;
    requests = 0;
    constructor(url) {
      assert.equal(url.origin, `ws://127.0.0.1:${port}`);
      assert.match(url.pathname, /^\/devtools\/page\/(good|closed)$/);
      queueMicrotask(() => {
        if (url.pathname.endsWith('/closed')) this.close();
        else { this.readyState = 1; this.onopen(); }
      });
    }
    send(raw) {
      const {id, method} = JSON.parse(raw);
      assert.equal(method, 'Runtime.evaluate');
      this.requests++;
      if (scenario === 'silent' || (scenario === 'retry' && this.requests === 1)) return;
      const result = {themeId:theme, visible:true, ready:true};
      if (scenario === 'media-error') result.error = 'fixture-decode-error';
      if (scenario === 'previous' && this.requests === 1) Object.assign(result, {themeId:'old', error:'old-decode-error'});
      if (scenario === 'wrong-theme') result.themeId = 'unrelated';
      if (scenario === 'hidden' || scenario === 'allow-hidden') result.visible = false;
      if (scenario === 'loading') result.ready = false;
      const reply = () => this.onmessage({data:JSON.stringify({id,result:{result:{value:result}}})});
      if (scenario === 'slow') setTimeout(reply,1700);
      else queueMicrotask(reply);
    }
    close() { this.readyState = 3; this.onclose?.(); }
  };
  process.argv = [process.execPath, 'fast-status.mjs', stateFile, theme, budget];
  if (scenario === 'allow-hidden') process.argv.push('--allow-hidden');
  await import('../engine/scripts/fast-status.mjs');
} else {
  const dir = await mkdtemp(path.join(os.tmpdir(),'aria-status-'));
  try {
    const stateFile = path.join(dir, 'state.json');
    await writeFile(stateFile, JSON.stringify({port,browserId:'fixture'}));
    const test = (scenario, budget, expectedError) => {
      const started = Date.now();
      const run = spawnSync(process.execPath, [fileURLToPath(import.meta.url),'--fixture',scenario,stateFile,String(budget)],
        {encoding:'utf8',timeout:budget+4000});
      assert.ifError(run.error);
      assert.equal(run.status, expectedError ? 2 : 0, scenario+' '+run.stderr);
      if (expectedError) assert.equal(run.stderr.trim(), expectedError, scenario);
      else assert.deepEqual(JSON.parse(run.stdout), {pass:true,themeId:theme,visible:scenario !== 'allow-hidden',ready:true}, scenario);
      return Date.now()-started;
    };
    test('retry',4000);
    test('slow',5000);
    const elapsed = test('silent',750,'window-not-ready');
    assert.ok(elapsed >= 700 && elapsed < 2200, 'Respect the configured deadline, elapsed '+elapsed);
    test('multiple',800);
    test('media-error',800,'fixture-decode-error');
    test('changed',800,'session-changed');
    test('previous',1200);
    test('allow-hidden',800);
    for (const scenario of ['wrong-theme','hidden','loading']) test(scenario,400,'window-not-ready');
    console.log('Skin status checks passed for delayed replies, deadline, target identity, decode errors and readiness.');
  } finally {
    await rm(dir,{recursive:true,force:true});
  }
}
