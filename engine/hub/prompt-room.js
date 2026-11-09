'use strict';
const AriaPrompts=(()=>{
 const categories=['全部','学习','写作','编程','规划','创作','自定义'];
 const starters=[
 {id:'notes',category:'学习',name:'把知识串起来',subtitle:'课堂笔记 → 复习提纲',icon:'book',tone:'mint',text:'请做我的学习搭子。先了解我的基础和目标，把笔记按知识点与逻辑关系整理成提纲，标出重点、疑问与需要补充的内容。用具体例子解释难点，最后给出几个自测问题，不编造笔记中没有的事实。',task:'请整理我接下来提供的课堂笔记，给出复习提纲、关键概念和自测问题。'},
 {id:'write',category:'写作',name:'让表达更自然',subtitle:'初稿 → 清楚的文字',icon:'spark',tone:'coral',text:'请做我的写作编辑。先明确读者、目的、语气与长度，保留原意和个人表达，调整句子顺序与衔接。对依据不足的内容指出缺口，不虚构事实。请给出修改稿，并简要说明关键改动。',task:'请润色我接下来提供的文字，让表达更清楚、自然，保留我的原意。'},
 {id:'debug',category:'编程',name:'一起解开小难题',subtitle:'现象与报错 → 排查步骤',icon:'sliders',tone:'blue',text:'请做我的开发搭档。结合代码、复现步骤、运行环境与报错定位问题，区分已确认事实与推测。优先给出最小的验证步骤和有依据的修复，说明如何确认修复有效。不要假设未提供的文件内容。',task:'请分析我接下来提供的报错与代码，给出可能原因、验证方法和修复建议。'},
 {id:'plan',category:'规划',name:'把今天安排妥当',subtitle:'目标与时间 → 可执行计划',icon:'list',tone:'peach',text:'请做我的计划搭子。根据截止时间、已有进展、可用时间和精力，把目标拆成具体小步骤。区分必须完成与可选事项，说明依赖关系，保留休息和缓冲，给出现在就能开始的一步。',task:'请根据我接下来提供的目标和时间，整理一份可执行、留有缓冲的小计划。'}
 ];
 const ideas=['先问我 3 个关键问题','给我一个具体例子','拆成可执行的小步骤','指出还缺哪些信息'];
 let category='全部',signature='',entered=false,dirty=false,draftTimer,previous=null,themeSignature='',draftKey='',editorReady=false;
 const fieldIds=['promptName','promptText','workTask','promptCategory','promptTone','promptFormat','promptDetail','promptSceneTheme','promptSceneOpacity'];
 const storeKey='ariaPromptDraftsV3';let drafts={version:3,activeKey:'',entries:{}};
 try{const saved=JSON.parse(localStorage.getItem(storeKey)||'null');if(saved?.version===3&&saved.entries&&typeof saved.entries==='object')drafts=saved;}catch{}
 function newKey(){return 'new:'+Date.now().toString(36)+':'+Math.random().toString(36).slice(2,8);}
 function snapshot(){return {promptId,draftKey,fields:Object.fromEntries(fieldIds.map(id=>[id,$(id).value]))};}
 function same(a,b){return JSON.stringify(a?.fields)===JSON.stringify(b?.fields)&&a?.promptId===b?.promptId;}
 function persist(){try{localStorage.setItem(storeKey,JSON.stringify(drafts));return true;}catch{$('promptDraftStatus').textContent='本机草稿空间已满，请先保存或复制当前内容';return false;}}
 function remember(checkpoint=false){
  clearTimeout(draftTimer);if(!editorReady)return true;
  const value=snapshot(),now=Date.now(),entry=drafts.entries[draftKey];let history=entry?.history||[],archived=false;
  if(entry?.value&&!same(entry.value,value)&&(checkpoint||!entry.checkpointAt||now-entry.checkpointAt>=30000)){
   history=[{at:entry.updatedAt||now,value:entry.value},...history].filter((item,i,all)=>all.findIndex(other=>same(item.value,other.value))===i).slice(0,6);archived=true;
  }
  drafts.entries[draftKey]={value,updatedAt:now,checkpointAt:archived?now:entry?.checkpointAt||0,history};drafts.activeKey=draftKey;
  const saved=persist();if(saved)$('promptDraftStatus').textContent='这份草稿已保存在本机';return saved;
 }
 function updateEditor(){
  $('deletePrompt').hidden=!promptId||!!state.prompts.find(p=>p.id===promptId)?.builtin;
  $('promptLength').textContent=$('promptText').value.length+' / 10000';signature='';render();
 }
 function restore(value){
  clearTimeout(draftTimer);promptId=value.promptId||null;draftKey=value.draftKey||(promptId?'template:'+promptId:newKey());
  fieldIds.forEach(id=>{$(id).value=String(value.fields?.[id]??'');});if(!$('promptCategory').value)$('promptCategory').value='自定义';
  if(!state.themes.some(t=>t.id===$('promptSceneTheme').value))$('promptSceneTheme').value='';
  editorReady=true;dirty=true;updateEditor();remember();
 }
 function changed(){dirty=true;$('promptLength').textContent=$('promptText').value.length+' / 10000';$('promptDraftStatus').textContent='正在保存草稿…';clearTimeout(draftTimer);draftTimer=setTimeout(()=>remember(),450);}
 function prepareSwitch(){if(!remember(true))return false;if(editorReady){previous=snapshot();$('promptUndoTemplate').hidden=false;}return true;}
 const historyButton=document.createElement('button');historyButton.id='promptHistory';historyButton.type='button';historyButton.className='text';historyButton.textContent='草稿与历史';$('promptUndoTemplate').before(historyButton);
 const historyDialog=document.createElement('dialog');historyDialog.id='promptHistoryDialog';historyDialog.className='library-edit-dialog';
 historyDialog.innerHTML='<div class="preview-top"><h2>草稿与历史</h2><button id="promptHistoryClose" class="circle" aria-label="关闭草稿与历史">×</button></div><label>选择草稿<select id="promptDraftChoice"></select></label><label>版本<select id="promptVersionChoice"></select></label><textarea id="promptHistoryText" readonly aria-label="草稿内容预览" style="width:100%;height:220px;resize:vertical"></textarea><div class="row"><button id="promptHistoryRestore" class="primary">恢复到编辑区</button></div>';
 document.body.append(historyDialog);
 function historyVersions(){const entry=drafts.entries[$('promptDraftChoice').value];return entry?[{at:entry.updatedAt,value:entry.value},...(entry.history||[])]:[];}
 function previewHistory(){const value=historyVersions()[Number($('promptVersionChoice').value)]?.value;$('promptHistoryText').value=value?[value.fields.promptName,value.fields.promptText,value.fields.workTask].filter(Boolean).join('\n\n'):'';}
 function chooseHistory(){const values=historyVersions();$('promptVersionChoice').innerHTML=values.map((v,i)=>'<option value="'+i+'">'+(i?'历史版本':'最新草稿')+' · '+esc(new Date(v.at).toLocaleString())+'</option>').join('');previewHistory();}
 historyButton.onclick=()=>{if(!remember(true))return;const entries=Object.entries(drafts.entries).filter(([,e])=>e?.value?.fields).sort((a,b)=>b[1].updatedAt-a[1].updatedAt);if(!entries.length){toast('写下内容后，这里会保留草稿和历史');return;}$('promptDraftChoice').innerHTML=entries.map(([key,e])=>'<option value="'+esc(key)+'">'+esc(e.value.fields.promptName||'未命名草稿')+'</option>').join('');$('promptDraftChoice').value=draftKey;chooseHistory();historyDialog.showModal();};
 $('promptDraftChoice').onchange=chooseHistory;$('promptVersionChoice').onchange=previewHistory;$('promptHistoryClose').onclick=()=>historyDialog.close();
 $('promptHistoryRestore').onclick=()=>{const value=historyVersions()[Number($('promptVersionChoice').value)]?.value;if(value&&prepareSwitch()){restore(value);historyDialog.close();toast('已恢复这份草稿，可以继续编辑');}};
 historyDialog.addEventListener('close',()=>{$('promptHistoryText').value='';$('promptDraftChoice').innerHTML='';$('promptVersionChoice').innerHTML='';});
 window.addEventListener('pagehide',()=>remember(true));document.addEventListener('visibilitychange',()=>{if(document.hidden)remember(true);});
 function group(p){const builtins={'builtin-study':'学习','builtin-write':'写作','builtin-code':'编程','builtin-plan':'规划'};if(builtins[p.id])return builtins[p.id];return categories.find(c=>c!=='全部'&&String(p.category||'').includes(c))||(p.builtin?'自定义':'自定义');}
 function render(){
  const next=JSON.stringify([state.prompts,category,promptId,$('promptSearch').value]);if(next!==signature){
   signature=next;const q=$('promptSearch').value.trim().toLowerCase();
   const prompts=state.prompts.filter(p=>(category==='全部'||group(p)===category)&&(!q||(p.name+' '+p.text).toLowerCase().includes(q)));
   $('promptList').innerHTML=prompts.map(p=>'<button class="prompt-item '+(p.id===promptId?'active':'')+'" data-prompt="'+esc(p.id)+'"><span class="prompt-bookmark"></span><b>'+esc(p.name)+'</b><small>'+esc(group(p))+' · '+(p.builtin?'内置模板':'我的收藏')+'</small></button>').join('');
   $('promptList').querySelectorAll('[data-prompt]').forEach(b=>b.onclick=()=>edit(b.dataset.prompt));$('promptListEmpty').hidden=prompts.length>0;
   $('promptTotal').textContent=state.prompts.length+' 份提示词收藏';
   $('promptCategories').innerHTML=categories.map(c=>'<button data-prompt-category="'+c+'" class="'+(category===c?'selected':'')+'">'+c+'</button>').join('');
  }
  const themes=JSON.stringify(state.themes.map(t=>[t.id,t.name]));if(themes!==themeSignature){
   themeSignature=themes;const value=$('promptSceneTheme').value;
   $('promptSceneTheme').innerHTML='<option value="">使用当前背景</option>'+state.themes.map(t=>'<option value="'+esc(t.id)+'">'+esc(t.name)+'</option>').join('');
   if(state.themes.some(t=>t.id===value))$('promptSceneTheme').value=value;
  }
 }
 function enter(){render();if(entered)return;entered=true;
  let saved=drafts.entries[drafts.activeKey]?.value;
  if(!saved){try{const legacy=JSON.parse(localStorage.getItem('ariaPromptDraftV2')||'null');if(legacy?.fields)saved={...legacy,draftKey:legacy.promptId?'template:'+legacy.promptId:newKey()};}catch{}}
  if(saved?.fields){restore(saved);$('promptDraftStatus').textContent='已恢复上次的草稿';}
  else if(state.prompts.length)edit(state.prompts[0].id,false);
  else{draftKey=newKey();editorReady=true;updateEditor();}
 }
 function edit(id,keepPrevious=true){
  const p=state.prompts.find(p=>p.id===id);if(!p)return;if(keepPrevious&&!prepareSwitch())return;
  const key='template:'+id,saved=drafts.entries[key]?.value;
  if(saved){restore(saved);$('promptDraftStatus').textContent='已恢复这份提示词的草稿';return;}
  clearTimeout(draftTimer);draftKey=key;promptId=id;$('promptName').value=p.name;$('promptText').value=p.text;$('workTask').value='';
  $('promptCategory').value=group(p);$('promptTone').value=p.tone||'';$('promptFormat').value=p.format||'';$('promptDetail').value=p.detail||'';
  $('promptSceneTheme').value=state.themes.some(t=>t.id===p.sceneThemeId)?p.sceneThemeId:'';$('promptSceneOpacity').value=p.sceneOpacity??'';
  editorReady=true;dirty=false;updateEditor();remember();
 }
 function useStarter(id){
  const t=starters.find(t=>t.id===id);if(!t||!prepareSwitch())return;
  draftKey='starter:'+id;const saved=drafts.entries[draftKey]?.value;if(saved){restore(saved);toast('已恢复这份任务模板的草稿');return;}
  promptId=null;
  $('promptName').value=t.name;$('promptText').value=t.text;$('workTask').value=t.task;$('promptCategory').value=t.category;
  $('promptTone').value='';$('promptFormat').value='';$('promptDetail').value='';$('promptSceneTheme').value='';$('promptSceneOpacity').value='';
  editorReady=true;updateEditor();changed();$('promptName').focus();toast('任务模板已载入，可以继续修改');
 }
 function compose(){
  const background=$('promptText').value.trim(),task=$('workTask').value.trim(),options=[];
  if($('promptTone').value)options.push('表达风格：'+$('promptTone').value);
  if($('promptFormat').value)options.push('输出形式：'+$('promptFormat').value);
  if($('promptDetail').value)options.push('内容长度：'+$('promptDetail').value);
  return '# 本次工作的背景与要求\n'+background+(options.length?'\n\n# 表达与输出偏好\n'+options.join('\n'):'')+(task?'\n\n# 这次要完成的任务\n'+task:'\n\n请先确认你理解以上工作要求，并问我这次想完成什么。');
 }
 $('promptStarters').innerHTML=starters.map(t=>'<button class="prompt-starter '+t.tone+'" data-starter="'+t.id+'"><span class="starter-icon"><i data-icon="'+t.icon+'"></i></span><span><b>'+t.name+'</b><small>'+t.subtitle+'</small></span><em>↗</em></button>').join('');icons();
 $('promptStarters').querySelectorAll('[data-starter]').forEach(b=>b.onclick=()=>useStarter(b.dataset.starter));
 $('promptIdeas').innerHTML=ideas.map((text,i)=>'<button data-prompt-idea="'+i+'">'+text+'</button>').join('');
 $('promptIdeas').onclick=e=>{const b=e.target.closest('[data-prompt-idea]');if(!b)return;const text=ideas[Number(b.dataset.promptIdea)];if(($('workTask').value+'\n'+text).length>2000){toast('本次任务最多 2000 字');return;}$('workTask').value+=($('workTask').value?'\n':'')+text+'。';changed();};
 $('promptBlocks').onclick=e=>{const b=e.target.closest('[data-prompt-block]');if(!b)return;const area=$('promptText'),start=area.selectionStart,block='\n\n【'+b.dataset.promptBlock+'】\n';if(area.value.length+block.length>10000){toast('背景与要求最多 10000 字');return;}area.setRangeText(block,start,area.selectionEnd,'end');area.focus();changed();};
 $('promptCategories').onclick=e=>{const b=e.target.closest('[data-prompt-category]');if(b){category=b.dataset.promptCategory;signature='';render();}};
 $('promptSearch').oninput=render;fieldIds.forEach(id=>{$(id).addEventListener('input',changed);$(id).addEventListener('change',changed);});
 $('newPrompt').onclick=()=>{if(!prepareSwitch())return;draftKey=newKey();editorReady=true;promptId=null;fieldIds.forEach(id=>$(id).value='');$('promptCategory').value='自定义';$('deletePrompt').hidden=true;changed();signature='';render();$('promptName').focus();};
 $('promptUndoTemplate').onclick=()=>{if(previous){const current=snapshot();if(!remember(true))return;restore(previous);previous=current;toast('已恢复替换前的内容');}};
 $('savePrompt').onclick=async()=>{
  if(!remember(true))return;const saving=snapshot(),key=draftKey,opacity=$('promptSceneOpacity').value;$('savePrompt').disabled=true;
  try{const r=await act('savePrompt',{promptId,name:$('promptName').value,text:$('promptText').value,category:$('promptCategory').value,tone:$('promptTone').value,format:$('promptFormat').value,detail:$('promptDetail').value,sceneThemeId:$('promptSceneTheme').value,sceneOpacity:opacity===''?null:Number(opacity)});
   if(r?.promptId){const savedKey='template:'+r.promptId;drafts.entries[savedKey]={...drafts.entries[key],value:{...saving,promptId:r.promptId,draftKey:savedKey}};
    if(key.startsWith('new:')&&key!==savedKey)delete drafts.entries[key];
    if(draftKey===key){promptId=r.promptId;draftKey=savedKey;dirty=false;remember();updateEditor();}else persist();
   }
  }finally{$('savePrompt').disabled=false;}
 };
 $('copyPrompt').onclick=()=>act('copy',{text:compose()});
 $('startPrompt').onclick=()=>{
  if(!$('promptText').value.trim()){toast('先写一点这次工作的背景吧 ♡');return;}
  const opacity=$('promptSceneOpacity').value;start($('promptSceneTheme').value||state.activeId,compose(),{sceneOpacity:opacity===''?null:Number(opacity)});
 };
 $('deletePrompt').onclick=async()=>{if(!promptId)return;const r=await act('deletePrompt',{promptId});if(r){$('newPrompt').click();}};
 $('promptPreview').onclick=()=>{$('promptComposedText').textContent=compose();$('promptComposedDialog').showModal();};$('promptComposedClose').onclick=()=>$('promptComposedDialog').close();
 return {render,enter,edit,compose,leave(){return remember(true);}};
})();
