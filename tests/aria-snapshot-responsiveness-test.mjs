import assert from 'node:assert/strict';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const {chromium}=require(process.env.ARIA_PLAYWRIGHT_MODULE||'playwright');
const root=path.resolve(process.argv[2]);
const signal=process.argv[3];
const server=http.createServer((req,res)=>{
  const rel=decodeURIComponent(new URL(req.url,'http://localhost').pathname).replace(/^\//,'')||'index.html';
  const file=path.resolve(root,rel);
  if(!file.startsWith(root+path.sep)){res.writeHead(403).end();return;}
  try{res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.css':'text/css','.svg':'image/svg+xml','.png':'image/png','.gif':'image/gif'})[path.extname(file)]||'application/octet-stream');res.end(fs.readFileSync(file));}catch{res.writeHead(404).end();}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
let browser;
try{
  browser=await chromium.launch({channel:'msedge',headless:true});
  const page=await browser.newPage({viewport:{width:1280,height:900}}),errors=[];
  page.on('pageerror',error=>errors.push(error.message));
  await page.addInitScript(()=>{
    const listeners=[];window.chrome=window.chrome||{};
    window.chrome.webview={addEventListener:(name,callback)=>listeners.push(callback),postMessage:request=>{
      setTimeout(()=>listeners.forEach(callback=>callback({data:{id:request.id,ok:true}})),20);
    }};
  });
  await page.goto('http://127.0.0.1:'+server.address().port+'/index.html');
  // The PowerShell test starts a deliberately delayed real snapshot worker only
  // after the browser is ready; this handshake prevents browser startup skew.
  fs.writeFileSync(signal+'.ready','ready');
  const deadline=Date.now()+20000;
  while(!fs.existsSync(signal+'.worker-started')){if(Date.now()>deadline)throw Error('Snapshot worker did not enter delayed collection');await new Promise(resolve=>setTimeout(resolve,50));}
  const started=Date.now();
  for(const id of ['library','settings','home','jobs','prompts','library']){
    await page.evaluate(pageId=>go(pageId),id);
    assert.equal(await page.locator('#'+id).evaluate(el=>el.classList.contains('active')),true);
  }
  assert.equal(fs.existsSync(signal+'.worker-finished'),false,'Snapshot completed before navigation test, so no responsiveness claim can be made');
  assert.ok(Date.now()-started<5000,'Client-side navigation took too long while collection ran');
  assert.deepEqual(errors,[]);
  console.log('Navigation remains responsive in the test browser while a real separate snapshot worker is busy.');
}finally{await browser?.close();await new Promise(resolve=>server.close(resolve));}
fs.writeFileSync(signal+'.browser-ok','passed');
