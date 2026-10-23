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
 let category='全部',signature='',entered=false,dirty=false,draftTimer,previous=null,themeSignature='';
 const fieldIds=['promptName','promptText','workTask','promptCategory','promptTone','promptFormat','promptDetail','promptSceneTheme','promptSceneOpacity'];
 function snapshot(){return {promptId,fields:Object.fromEntries(fieldIds.map(id=>[id,$(id).value]))};}
 function restore(value){promptId=value.promptId||null;fieldIds.forEach(id=>{$(id).value=value.fields?.[id]??'';});if(!$('promptCategory').value)$('promptCategory').value='自定义';dirty=true;signature='';render();changed();}
 function remember(){try{localStorage.setItem('ariaPromptDraftV2',JSON.stringify(snapshot()));$('promptDraftStatus').textContent='草稿已保存在本机';}catch{$('promptDraftStatus').textContent='草稿暂未保存';}}
 function changed(){dirty=true;$('promptLength').textContent=$('promptText').value.length+' / 10000';$('promptDraftStatus').textContent='正在保存草稿…';clearTimeout(draftTimer);draftTimer=setTimeout(remember,450);}
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
  let saved;try{saved=JSON.parse(localStorage.getItem('ariaPromptDraftV2')||'null')}catch{}
  if(saved?.fields){restore(saved);$('promptDraftStatus').textContent='已恢复上次的草稿';}
  else if(state.prompts.length)edit(state.prompts[0].id,false);
 }
 function rememberPrevious(){previous=snapshot();$('promptUndoTemplate').hidden=false;}
 function edit(id,keepPrevious=true){
  const p=state.prompts.find(p=>p.id===id);if(!p)return;if(keepPrevious&&dirty)rememberPrevious();
  promptId=id;$('promptName').value=p.name;$('promptText').value=p.text;$('workTask').value='';
  $('promptCategory').value=group(p);$('promptTone').value=p.tone||'';$('promptFormat').value=p.format||'';$('promptDetail').value=p.detail||'';
  $('promptSceneTheme').value=state.themes.some(t=>t.id===p.sceneThemeId)?p.sceneThemeId:'';$('promptSceneOpacity').value=p.sceneOpacity??'';
  $('deletePrompt').hidden=!!p.builtin;dirty=false;signature='';render();$('promptLength').textContent=p.text.length+' / 10000';remember();
 }
 function useStarter(id){
  const t=starters.find(t=>t.id===id);if(!t)return;rememberPrevious();promptId=null;
  $('promptName').value=t.name;$('promptText').value=t.text;$('workTask').value=t.task;$('promptCategory').value=t.category;
  $('promptTone').value='';$('promptFormat').value='';$('promptDetail').value='';$('promptSceneTheme').value='';$('promptSceneOpacity').value='';
  $('deletePrompt').hidden=true;changed();signature='';render();$('promptName').focus();toast('任务模板已载入，可以继续修改');
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
 $('newPrompt').onclick=()=>{rememberPrevious();promptId=null;fieldIds.forEach(id=>$(id).value='');$('promptCategory').value='自定义';$('deletePrompt').hidden=true;changed();signature='';render();$('promptName').focus();};
 $('promptUndoTemplate').onclick=()=>{if(previous){const current=snapshot();restore(previous);previous=current;toast('已恢复替换前的内容');}};
 $('savePrompt').onclick=async()=>{
  const opacity=$('promptSceneOpacity').value;
  const r=await act('savePrompt',{promptId,name:$('promptName').value,text:$('promptText').value,category:$('promptCategory').value,tone:$('promptTone').value,format:$('promptFormat').value,detail:$('promptDetail').value,sceneThemeId:$('promptSceneTheme').value,sceneOpacity:opacity===''?null:Number(opacity)});
  if(r?.promptId){promptId=r.promptId;dirty=false;remember();signature='';render();}
 };
 $('copyPrompt').onclick=()=>act('copy',{text:compose()});
 $('startPrompt').onclick=()=>{
  if(!$('promptText').value.trim()){toast('先写一点这次工作的背景吧 ♡');return;}
  const opacity=$('promptSceneOpacity').value;start($('promptSceneTheme').value||state.activeId,compose(),{sceneOpacity:opacity===''?null:Number(opacity)});
 };
 $('deletePrompt').onclick=async()=>{if(!promptId)return;const r=await act('deletePrompt',{promptId});if(r){$('newPrompt').click();}};
 $('promptPreview').onclick=()=>{$('promptComposedText').textContent=compose();$('promptComposedDialog').showModal();};$('promptComposedClose').onclick=()=>$('promptComposedDialog').close();
 return {render,enter,edit,compose};
})();
