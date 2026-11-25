import fs from 'node:fs/promises';
import {setTimeout as delay} from 'node:timers/promises';

const [stateFile, expectedTheme, timeoutArg='8000'] = process.argv.slice(2);
const deadline = Date.now() + Number(timeoutArg);
const diagnosticHidden = process.argv.includes('--allow-hidden');
const sockets = [];
let sequence = 0;

const expression = `(() => {const s=window.__CODEX_DREAM_SKIN_STATE__,h=document.getElementById('dream-skin-window-background'),m=h?.querySelector('img,video');return {themeId:s?.themeId,visible:!document.hidden,ready:!!h&&!!m&&(m.tagName==='VIDEO'?s?.mediaDecoded:!!m.complete&&m.naturalWidth>0),error:s?.mediaError};})()`;

function remaining(limit) {
  return Math.max(0, Math.min(limit, deadline - Date.now()));
}

async function probeWindow(url) {
  const ws = new WebSocket(url);
  sockets.push(ws);
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(Error('connect-timeout')), remaining(1500));
    ws.onopen = () => { clearTimeout(timer); resolve(); };
    ws.onerror = ws.onclose = () => { clearTimeout(timer); reject(Error('window-closed')); };
  });

  let responseBudget = 1500;
  while (Date.now() < deadline && ws.readyState === WebSocket.OPEN) {
    const id = ++sequence;
    const result = await new Promise((resolve, reject) => {
      const timer = setTimeout(() => resolve(null), remaining(responseBudget));
      ws.onerror = ws.onclose = () => { clearTimeout(timer); reject(Error('window-closed')); };
      ws.onmessage = event => {
        let message;
        try { message = JSON.parse(event.data); } catch { return; }
        if (message.id !== id) return;
        clearTimeout(timer);
        resolve(message.result?.result?.value ?? null);
      };
      ws.send(JSON.stringify({id, method:'Runtime.evaluate', params:{expression, returnByValue:true}}));
    });
    if (result && (!expectedTheme || expectedTheme === '*' || result.themeId === expectedTheme)) {
      if (result.error) throw Error(result.error);
      if (result.ready && (result.visible || diagnosticHidden)) return result;
    }
    // A busy renderer can miss the initial reply while decoding a new video.
    // Give the retry more time, within this switch's original deadline.
    if (result === null) responseBudget *= 2;
    await delay(remaining(200));
  }
  throw Error('window-not-ready');
}

try {
  const state = JSON.parse(await fs.readFile(stateFile, 'utf8'));
  const options = () => ({signal:AbortSignal.timeout(remaining(1500))});
  const version = await (await fetch(`http://127.0.0.1:${state.port}/json/version`, options())).json();
  if (!version.webSocketDebuggerUrl?.endsWith('/'+state.browserId)) throw Error('session-changed');
  const targets = await (await fetch(`http://127.0.0.1:${state.port}/json/list`, options())).json();
  const windows = [];
  for (const target of targets.filter(t => t.type === 'page' && t.url.startsWith('app:'))) {
    const url = new URL(target.webSocketDebuggerUrl);
    if (url.hostname === '127.0.0.1' && Number(url.port) === Number(state.port)) windows.push(url);
  }
  let pass;
  try {
    pass = await Promise.any(windows.map(probeWindow));
  } catch (errors) {
    throw errors.errors?.find(error => error.message !== 'window-not-ready') || Error('window-not-ready');
  }
  console.log(JSON.stringify({pass:true, ...pass}));
} catch (error) {
  console.error(error.message);
  process.exitCode = 2;
} finally {
  for (const ws of sockets) ws.close();
}
