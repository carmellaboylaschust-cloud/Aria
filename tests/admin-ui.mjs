import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const {chromium}=require(process.env.ARIA_PLAYWRIGHT_MODULE||'playwright');
const root=path.resolve(process.argv[2]||'engine/hub');
const server=http.createServer((req,res)=>{
 const rel=decodeURIComponent(new URL(req.url,'http://localhost').pathname).replace(/^\//,'')||'index.html';
 const file=path.resolve(root,rel);
 if(!file.startsWith(path.resolve(root)+path.sep)){res.writeHead(403).end();return;}
 try{const ext=path.extname(file);res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.css':'text/css','.svg':'image/svg+xml'})[ext]||'application/octet-stream');res.end(fs.readFileSync(file));}catch{res.writeHead(404).end();}
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
let browser;const errors=[];
try{
 browser=await chromium.launch({channel:'msedge',headless:true});
 const page=await browser.newPage({viewport:{width:1280,height:900}});
 page.on('pageerror',e=>errors.push(e.message));
 await page.addInitScript(()=>{
  let initialized=false;const listeners=[];window.testRequests=[];
  window.chrome=window.chrome||{};window.chrome.webview={addEventListener:(name,cb)=>listeners.push(cb),postMessage:request=>{
   window.testRequests.push(request.action);let response={id:request.id,ok:true};
   if(request.action==='privacyStatus')response.initialized=initialized;
   if(request.action==='privacySetup'){initialized=true;response.message='管理员已设置';}
   if(request.action==='privacyAdminLogin')response.questions=[{id:'fixture',question:'测试问题'}];
   setTimeout(()=>listeners.forEach(cb=>cb({data:response})),0);
  }};
 });
 await page.goto('http://127.0.0.1:'+server.address().port+'/index.html');
 await page.evaluate(()=>AriaPrivacy.openAdmin());
 await page.locator('#privacySetup').waitFor({state:'visible'});
 await page.locator('#setupPassword').fill('fixture-password-2026');
 await page.locator('#setupConfirmation').fill('fixture-password-2026');
 await page.locator('#setupQuestion').fill('你最喜欢哪一片天空？');
 await page.locator('#setupAnswer').fill('海盐珊瑚');
 await page.locator('#privacySetupSave').click();
 await page.locator('#adminLogin').waitFor({state:'visible'});
 if(await page.locator('#setupPassword').inputValue())throw new Error('Setup secret retained');
 await page.locator('#adminPassword').fill('fixture-password-2026');
 await page.locator('#adminSubmit').click();
 await page.locator('#questionEditor').waitFor({state:'visible'});
 await page.locator('#questionCancel').click();
 await page.waitForFunction(()=>window.testRequests.includes('privacyAdminLock'));
 await page.evaluate(()=>AriaPrivacy.openAdmin());
 await page.locator('#adminLogin').waitFor({state:'visible'});
 if(await page.locator('#privacySetup').isVisible())throw new Error('Existing user was sent to setup');
 if(errors.length)throw new Error(errors.join('\n'));
 console.log('Administrator UI: setup, Chinese input value, secret clearing, existing login, close-lock passed.');
}finally{await browser?.close();server.close();}
