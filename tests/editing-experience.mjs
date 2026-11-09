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
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));let browser;
try{
 browser=await chromium.launch({channel:'msedge',headless:true});const page=await browser.newPage({viewport:{width:1440,height:1100}}),errors=[];
 page.on('pageerror',error=>errors.push(error.message));
 await page.addInitScript(()=>{
  const listeners=[];window.testRequests=[];window.chrome=window.chrome||{};
  window.chrome.webview={addEventListener:(name,cb)=>listeners.push(cb),postMessage:request=>{window.testRequests.push(request);setTimeout(()=>listeners.forEach(cb=>cb({data:{id:request.id,ok:true,promptId:request.action==='savePrompt'?'custom-fixture':undefined}})),0);}};
  if(!localStorage.getItem('legacyTestSeeded')){localStorage.setItem('legacyTestSeeded','1');localStorage.setItem('ariaPromptDraftV2',JSON.stringify({promptId:'p1',fields:{promptName:'旧草稿',promptText:'继续保留中文草稿',workTask:'原本的任务',promptCategory:'自定义'}}));}
 });
 const populate=()=>page.evaluate(()=>acceptState({themes:[{id:'one',name:'Fixture One',kind:'image',group:'A',tags:['one-tag'],url:'media/video-placeholder.svg',sizeMB:1},{id:'two',name:'Fixture Two',kind:'image',group:'B',tags:['two-tag'],url:'media/video-placeholder.svg',sizeMB:2}],jobs:[],heroes:[],prompts:[{id:'p1',name:'First',text:'Saved first',category:'自定义'},{id:'p2',name:'Second',text:'Saved second',category:'自定义'}],favorites:[],hiddenThemes:[],hiddenUnlocked:false,activeId:'',freeGB:100,policy:{videoMaxMB:512,sceneMaxMB:1024},playbackSettings:{mode:'normal',audioEnabled:false},privacySettings:{safeThemeId:''}}));
 await page.goto('http://127.0.0.1:'+server.address().port+'/index.html');await populate();
 await page.evaluate(()=>{go('library');AriaLibrary.open(['one','two'],true);});
 assert.equal(await page.locator('#libraryEditGroup').isDisabled(),true);assert.equal(await page.locator('#libraryTags').isDisabled(),true);
 await page.locator('#libraryGroupMode').selectOption('replace');await page.locator('#libraryEditGroup').fill('Together');await page.locator('#libraryEditSave').click();await page.waitForFunction(()=>!document.getElementById('libraryEditDialog').open);
 let result=await page.evaluate(()=>({request:window.testRequests.filter(r=>r.action==='saveLibraryMeta').at(-1),themes:state.themes}));
 assert.equal(result.request.group,'Together');assert.equal('tags' in result.request,false);assert.deepEqual(result.themes.map(t=>t.tags),[['one-tag'],['two-tag']]);
 await page.evaluate(()=>AriaLibrary.open(['one','two'],true));await page.locator('#libraryTagsMode').selectOption('replace');await page.locator('#libraryTags').fill('new-tag');await page.locator('#libraryEditSave').click();await page.waitForFunction(()=>!document.getElementById('libraryEditDialog').open);
 result=await page.evaluate(()=>({request:window.testRequests.filter(r=>r.action==='saveLibraryMeta').at(-1),themes:state.themes}));assert.equal('group' in result.request,false);assert.deepEqual(result.themes.map(t=>t.group),['Together','Together']);
 await page.evaluate(()=>AriaLibrary.open(['one','two'],true));await page.locator('#libraryGroupMode').selectOption('clear');await page.locator('#libraryEditSave').click();await page.waitForFunction(()=>!document.getElementById('libraryEditDialog').open);
 result=await page.evaluate(()=>({request:window.testRequests.filter(r=>r.action==='saveLibraryMeta').at(-1),themes:state.themes}));assert.equal(result.request.group,'');assert.equal('tags' in result.request,false);assert.deepEqual(result.themes.map(t=>t.tags),[['new-tag'],['new-tag']]);
 await page.evaluate(()=>go('prompts'));assert.equal(await page.locator('#promptText').inputValue(),'继续保留中文草稿');
 await page.evaluate(()=>{document.getElementById('promptText').value='切换前尚未等到自动保存';document.getElementById('promptText').dispatchEvent(new Event('input'));AriaPrompts.edit('p2');document.getElementById('promptText').value='第二份中文草稿';document.getElementById('promptText').dispatchEvent(new Event('input'));AriaPrompts.edit('p1');});
 assert.equal(await page.locator('#promptText').inputValue(),'切换前尚未等到自动保存');
 for(let i=0;i<10;i++)await page.evaluate(i=>{document.getElementById('promptText').value='历史内容 '+i;document.getElementById('promptText').dispatchEvent(new Event('input'));AriaPrompts.edit('p2');AriaPrompts.edit('p1');},i);
 let saved=await page.evaluate(()=>JSON.parse(localStorage.getItem('ariaPromptDraftsV3')));assert.equal(saved.entries['template:p1'].history.length,6);assert.equal(saved.entries['template:p2'].value.fields.promptText,'第二份中文草稿');
 await page.locator('#promptHistory').click();await page.locator('#promptVersionChoice').selectOption('1');assert.match(await page.locator('#promptHistoryText').inputValue(),/历史内容 8/);await page.locator('#promptHistoryRestore').click();assert.equal(await page.locator('#promptText').inputValue(),'历史内容 8');
 await page.reload();await populate();await page.evaluate(()=>go('prompts'));assert.equal(await page.locator('#promptText').inputValue(),'历史内容 8');await page.evaluate(()=>AriaPrompts.edit('p2'));assert.equal(await page.locator('#promptText').inputValue(),'第二份中文草稿');
 await page.locator('#newPrompt').click();await page.locator('#promptName').fill('独立草稿');await page.locator('#promptText').fill('待完成');await page.locator('#newPrompt').click();await page.locator('#promptHistory').click();assert.match(await page.locator('#promptDraftChoice').textContent(),/独立草稿/);await page.locator('#promptHistoryClose').click();
 assert.deepEqual(errors,[]);console.log('Editing experience checks passed: partial batch updates, explicit clearing, migration, rapid switching, Chinese drafts, six-version bound, restore, reload and independent new drafts.');
}finally{await browser?.close();await new Promise(resolve=>server.close(resolve));}
