import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import {createRequire} from 'node:module';
const {chromium}=createRequire(import.meta.url)(process.env.ARIA_PLAYWRIGHT_MODULE||'playwright');
const root=path.resolve(process.argv[2]);
const server=http.createServer((req,res)=>{const p=path.resolve(root,'.'+new URL(req.url,'http://localhost').pathname);if(!p.startsWith(root+path.sep))return res.writeHead(403).end();try{res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.css':'text/css','.svg':'image/svg+xml'})[path.extname(p)]||'application/octet-stream');res.end(fs.readFileSync(p));}catch{res.writeHead(404).end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
try{
 browser=await chromium.launch({channel:'msedge',headless:true});const page=await browser.newPage({viewport:{width:1440,height:900}});const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.addInitScript(()=>{
  const listeners=[];
  window.calls=[];
  window.fromAria=data=>listeners.forEach(listener=>listener({data}));
  window.chrome={webview:{
   addEventListener:(_,listener)=>listeners.push(listener),
   postMessage:request=>{
    window.calls.push(request);
    const extra=request.action==='queuePause'?{queueSettings:{paused:request.paused,priorityIds:[]}}:{};
    setTimeout(()=>window.fromAria({id:request.id,ok:true,...extra}),10);
   }
  }};
 });
 await page.goto('http://127.0.0.1:'+server.address().port+'/index.html');
 await page.evaluate(()=>acceptState({themes:Array.from({length:180},(_,i)=>({id:'fixture-'+i,name:'壁纸 '+i,kind:'image',url:'media/video-placeholder.svg',thumbnail:'media/video-placeholder.svg',sizeMB:2,dimensions:'3840 × 2160',addedAt:'2026-01-01'})),heroes:[],jobs:[{id:'job-fixture',name:'测试队列',status:'queued',percent:0}],prompts:[],favorites:[],hiddenThemes:[],hiddenUnlocked:false,activeId:'fixture-0',freeGB:100,queueSettings:{paused:false,priorityIds:[]},previousAvailable:true,policy:{videoMaxMB:512,sceneMaxMB:1024},privacySettings:{},playbackSettings:{}}));
 await page.evaluate(()=>go('library'));await page.waitForTimeout(300);
 await page.evaluate(()=>{window.scrollTo(0,1250);window.keepNode=document.querySelector('[data-card-id="fixture-5"]');});
 await page.evaluate(()=>go('settings'));await page.waitForTimeout(100);await page.evaluate(()=>go('library'));await page.waitForTimeout(200);
 assert.ok(await page.evaluate(()=>Math.abs(window.scrollY-1250)<5),'library scroll restored');
 await page.evaluate(()=>renderLibrary());assert.ok(await page.evaluate(()=>window.keepNode===document.querySelector('[data-card-id="fixture-5"]')),'unchanged card retained');
 await page.locator('#skinGrid [data-favorite="fixture-1"]').click();await page.waitForTimeout(80);
 assert.equal(await page.locator('#preview').evaluate(e=>e.open),false,'favorite stays in library');
 assert.equal(await page.locator('#skinGrid [data-favorite="fixture-1"]').getAttribute('aria-pressed'),'true');
 assert.ok(await page.evaluate(()=>window.keepNode===document.querySelector('[data-card-id="fixture-5"]')));
 assert.equal(await page.evaluate(()=>document.activeElement?.dataset.favorite),'fixture-1','favorite keeps keyboard focus');
 await page.locator('#manageSkins').click();await page.locator('#skinGrid [data-theme="fixture-2"]').click();assert.equal(await page.evaluate(()=>document.activeElement?.dataset.theme),'fixture-2','selection keeps keyboard focus');await page.locator('#manageSkins').click();
 await page.locator('#search').fill('壁纸 17');await page.waitForTimeout(200);assert.equal(await page.locator('#skinGrid .card').count(),11);
 await page.evaluate(()=>go('home'));await page.waitForTimeout(50);await page.evaluate(()=>go('library'));await page.waitForTimeout(60);assert.equal(await page.locator('#search').inputValue(),'壁纸 17');
 const apply=page.locator('#applySelected');
 await page.locator('#skinGrid [data-theme="fixture-17"]').click();
 await apply.click();
 await page.waitForFunction(()=>!document.getElementById('preview').open);
 await page.locator('#skinGrid [data-theme="fixture-170"]').click();
 assert.equal(await apply.isDisabled(),true,'the second preview shows the first request is still running');
 assert.equal(await apply.textContent(),'正在应用背景…');
 await page.evaluate(()=>window.fromAria({type:'launchDone',message:'第一张加载失败'}));
 assert.equal(await apply.isEnabled(),true,'a failed apply releases the next preview');
 assert.equal(await apply.textContent(),'应用到桌面端');
 assert.equal(await page.locator('#toast').textContent(),'第一张加载失败');
 await apply.click();
 await page.waitForFunction(()=>!document.getElementById('preview').open);
 await page.evaluate(()=>window.fromAria({type:'launchDone',message:'第二张已应用'}));
 assert.equal(await page.locator('#toast').textContent(),'第二张已应用');
 assert.equal(await apply.isEnabled(),true);
 assert.deepEqual(await page.evaluate(()=>calls.filter(request=>request.action==='launch').map(request=>request.themeId)),['fixture-17','fixture-170']);
 await page.evaluate(()=>go('jobs'));await page.locator('#queuePause').click();await page.waitForTimeout(100);assert.equal(await page.locator('#queuePause').textContent(),'继续队列');assert.ok(await page.locator('#queuePausedNote').isVisible());assert.equal(await page.locator('[data-priority]').count(),1);
 await page.locator('[data-priority]').click();assert.ok(await page.evaluate(()=>calls.some(r=>r.action==='queuePriority'&&r.jobId==='job-fixture')));
 await page.evaluate(()=>go('library'));await page.locator('#previousSkin').click();assert.ok(await page.evaluate(()=>calls.some(r=>r.action==='launch'&&r.restorePrevious===true)));
 assert.deepEqual(errors,[]);console.log('PASS: retained scroll/filter, keyed cards, direct favorite, search, pause/priority, previous-skin request, no page errors');
 if(process.env.ARIA_TEST_SCREENSHOT){await page.screenshot({path:process.env.ARIA_TEST_SCREENSHOT,fullPage:false});}
}finally{await browser?.close();await new Promise(r=>server.close(r));}
