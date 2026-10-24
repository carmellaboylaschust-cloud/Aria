import assert from 'node:assert/strict';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const {chromium}=require(process.env.ARIA_PLAYWRIGHT_MODULE||'playwright');
const root=path.resolve(process.argv[2]);
const server=http.createServer((req,res)=>{
 const rel=decodeURIComponent(new URL(req.url,'http://localhost').pathname).replace(/^\//,'')||'index.html';
 const file=path.resolve(root,rel);if(!file.startsWith(root+path.sep)){res.writeHead(403).end();return;}
 try{res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.css':'text/css','.svg':'image/svg+xml'})[path.extname(file)]||'application/octet-stream');res.end(fs.readFileSync(file));}catch{res.writeHead(404).end();}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
let browser;
try{
 browser=await chromium.launch({channel:'msedge',headless:true});
 const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[];
 page.on('pageerror',error=>errors.push(error.message));
 await page.addInitScript(()=>{
  const listeners=[];window.testRequests=[];window.chrome=window.chrome||{};
  window.chrome.webview={addEventListener:(name,cb)=>listeners.push(cb),postMessage:request=>{window.testRequests.push(request);setTimeout(()=>listeners.forEach(cb=>cb({data:{id:request.id,ok:true}})),0);}};
 });
 await page.goto('http://127.0.0.1:'+server.address().port+'/index.html');
 await page.evaluate(()=>acceptState({themes:[{id:'video-fixture',kind:'video',name:'Video fixture',url:'data:video/mp4;base64,AA',sizeMB:317},{id:'image-fixture',kind:'image',name:'Image fixture',url:'media/video-placeholder.svg',sizeMB:1}],jobs:[],heroes:[],prompts:[],favorites:[],hiddenThemes:[],hiddenUnlocked:false,activeId:'video-fixture',freeGB:100,policy:{videoMaxMB:512,sceneMaxMB:1024,autoImportWorkshop:false},playbackSettings:{mode:'normal',audioEnabled:false},privacySettings:{safeThemeId:''}}));
 assert.equal(await page.locator('#skinGrid video').count(),0);
 assert.match(await page.locator('#skinGrid [data-theme="video-fixture"] img').getAttribute('src'),/video-placeholder.svg/);
 await page.evaluate(()=>{go('library');openPreview('video-fixture');});
 await page.locator('#videoAudio').waitFor({state:'visible'});
 assert.equal(await page.locator('#videoAudio').isChecked(),false);
 await page.locator('#videoAudio').check();
 await page.waitForFunction(()=>window.testRequests.some(r=>r.action==='saveVideoAudio'&&r.enabled===true));
 await page.waitForFunction(()=>!document.getElementById('videoAudio').disabled);
 assert.equal(await page.locator('#previewMedia video').evaluate(video=>video.muted),true);
 await page.evaluate(()=>{closePreview();openPreview('image-fixture');});
 assert.equal(await page.locator('#videoAudioRow').isVisible(),false);
 await page.evaluate(()=>{closePreview();go('settings');});
 assert.equal(await page.locator('#settingsVideoAudio').isChecked(),true);
 await page.locator('#settingsVideoAudio').uncheck();
 await page.waitForFunction(()=>window.testRequests.some(r=>r.action==='saveVideoAudio'&&r.enabled===false));
 assert.deepEqual(errors,[]);
 console.log('Video library UI checks passed: static cards, cover fallback, audio switch, muted preview, image layout, settings synchronization.');
}finally{await browser?.close();await new Promise(resolve=>server.close(resolve));}
