'use strict';
const AriaPrivacy=(()=>{
 let allowHidden=false,challengeId='',busy=false,questions=[];
 const chooseFilter=value=>{filter=value;uninstallSelection.clear();document.querySelectorAll('[data-filter]').forEach(b=>b.classList.toggle('selected',b.dataset.filter===value));renderLibrary();};
 function purge(){
  $('toast').classList.remove('show');$('jobCompletionAction').hidden=true;
  if(typeof AriaLibrary!=='undefined')AriaLibrary.lock();
  if($('privacySetup').open)$('privacySetup').close();
  if($('questionEditor').open)$('questionEditor').close();if($('adminLogin').open)$('adminLogin').close();
  allowHidden=false;state.hiddenThemes=[];state.hiddenUnlocked=false;uninstallSelection.clear();uninstallReview=[];$('uninstallNames').innerHTML='';$('uninstallSummary').textContent='';
  if(selected&&!state.themes.some(t=>t.id===selected.id)){closePreview();selected=null;}
  if($('uninstallDialog').open)$('uninstallDialog').close();
  if(filter==='hidden')chooseFilter('all');
  lastSignature='';renderLibrary();
 }
 function lock(){purge();send('privacyLock').catch(()=>{});}
 function prepareState(data){
  if(!allowHidden)return {...data,hiddenThemes:[],hiddenUnlocked:false};
  if(data.hiddenUnlocked===false){purge();toast('隐藏皮肤已锁定，请重新回答问题');}
  return data;
 }
 async function enter(){
  if(state.hiddenUnlocked&&allowHidden){chooseFilter('hidden');return;}
  if(busy)return;busy=true;
  try{const status=await send('privacyStatus');if(status.initialized===false){busy=false;openSetup();return;}}catch(e){busy=false;toast(e.message);return;}
  $('privacyError').textContent='';$('privacyAnswer').value='';$('privacyQuestion').textContent='正在准备问题…';
  $('privacySubmit').disabled=true;$('privacyGate').showModal();
  try{const result=await send('privacyChallenge');challengeId=result.challengeId;$('privacyQuestion').textContent=result.question;$('privacySubmit').disabled=false;$('privacyAnswer').focus();}
  catch(e){$('privacyError').textContent=e.message;}finally{busy=false;}
 }
 $('filters').onclick=e=>{
  const b=e.target.closest('[data-filter]');if(!b)return;
  if(b.dataset.filter==='hidden'){enter();return;}
  if(filter==='hidden')lock();chooseFilter(b.dataset.filter);
 };
 $('privacyCancel').onclick=()=>$('privacyGate').close();
 $('privacyGate').addEventListener('close',()=>{$('privacyAnswer').value='';challengeId='';});
 $('privacyForm').onsubmit=async e=>{
  e.preventDefault();if(busy||!challengeId)return;busy=true;$('privacySubmit').disabled=true;$('privacyError').textContent='';
  const answer=$('privacyAnswer').value;$('privacyAnswer').value='';
  try{await send('privacyAnswer',{challengeId,answer});allowHidden=true;state.hiddenUnlocked=true;$('privacyGate').close();chooseFilter('hidden');toast('已解锁隐藏皮肤');}
  catch(err){$('privacyError').textContent=err.message;$('privacyAnswer').focus();}
  finally{busy=false;$('privacySubmit').disabled=false;}
 };
 $('lockHidden').onclick=lock;
 async function move(ids,hidden){
  if(!ids.length)return;
  try{const status=await send('privacyStatus');if(status.initialized===false){openSetup();return;}}catch(e){toast(e.message);return;}
  const result=await act('hideThemes',{themeIds:ids,hidden});if(!result)return;
  const changed=new Set(result.changedIds||ids),from=hidden?state.themes:state.hiddenThemes,moved=from.filter(t=>changed.has(t.id));
  state.themes=state.themes.filter(t=>!changed.has(t.id));state.hiddenThemes=(state.hiddenThemes||[]).filter(t=>!changed.has(t.id));
  if(hidden){if(allowHidden)state.hiddenThemes.push(...moved);state.favorites=state.favorites.filter(id=>!changed.has(id));}
  else state.themes.push(...moved);
  if(selected&&changed.has(selected.id)){closePreview();selected=null;}
  uninstallSelection.clear();lastSignature='';renderLibrary();renderRecent();renderCurrent();$('libraryCount').textContent=state.themes.length;
 }
 $('hideSkins').onclick=()=>move([...uninstallSelection],filter!=='hidden');
 $('hideSelected').onclick=()=>{if(selected)move([selected.id],!state.hiddenThemes?.some(t=>t.id===selected.id));};
 function updateControls(){
  const unlocked=filter==='hidden'&&state.hiddenUnlocked&&allowHidden;
  $('hiddenBar').hidden=!unlocked;
  $('hideSkins').textContent=unlocked?'移回普通列表':'移入隐藏皮肤';$('hideSkins').disabled=uninstallBusy||!uninstallSelection.size;
 }
 function previewControl(){
  $('hideSelected').textContent=state.hiddenThemes?.some(t=>t.id===selected?.id)?'移回普通列表':'隐藏这张';
  $('hideSelected').disabled=selected?.id===state.activeId&&!state.hiddenThemes?.some(t=>t.id===selected?.id);
 }
 async function openAdmin(){
  try{const status=await send('privacyStatus');if(status.initialized===false){openSetup();return;}}catch(e){toast(e.message);return;}

  if($('privacyGate').open)$('privacyGate').close();
  $('adminPassword').value='';$('adminError').textContent='';$('adminLogin').showModal();$('adminPassword').focus();
 }
 function openSetup(){
  if($('privacyGate').open)$('privacyGate').close();
  $('privacySetupForm').reset();$('privacySetupError').textContent='';
  if(!$('privacySetup').open)$('privacySetup').showModal();$('setupPassword').focus();
 }
 $('privacySetupCancel').onclick=()=>$('privacySetup').close();
 $('privacySetup').addEventListener('close',()=>$('privacySetupForm').reset());
 $('privacySetupForm').onsubmit=async e=>{
  e.preventDefault();const button=$('privacySetupSave');if(button.disabled)return;
  const password=$('setupPassword').value,confirmation=$('setupConfirmation').value;
  const questions=[{question:$('setupQuestion').value,answer:$('setupAnswer').value}];
  $('privacySetupError').textContent='';
  if(password!==confirmation){$('privacySetupError').textContent='请确认两次密码完全一致';return;}
  button.disabled=true;
  try{const r=await send('privacySetup',{password,confirmation,questions});$('privacySetupForm').reset();$('privacySetup').close();toast(r.message);await openAdmin();}
  catch(err){$('privacySetupError').textContent=err.message;}
  finally{button.disabled=false;}
 };
 $('manageQuestions').onclick=$('gateManageQuestions').onclick=openAdmin;
 $('adminCancel').onclick=()=>$('adminLogin').close();
 $('adminLogin').addEventListener('close',()=>$('adminPassword').value='');
 $('adminForm').onsubmit=async e=>{
  e.preventDefault();const password=$('adminPassword').value;$('adminPassword').value='';$('adminSubmit').disabled=true;$('adminError').textContent='';
  try{const result=await send('privacyAdminLogin',{password});questions=(result.questions||[]).map(q=>({...q,answer:''}));$('adminLogin').close();renderQuestions();$('questionEditor').showModal();}
  catch(err){$('adminError').textContent=err.message;$('adminPassword').focus();}finally{$('adminSubmit').disabled=false;}
 };
 function readQuestions(){return [...$('questionRows').children].map(row=>({id:row.dataset.id,question:row.querySelector('.question-text').value,answer:row.querySelector('.question-answer').value}));}
 function renderQuestions(){
  $('questionError').textContent='';
  $('questionRows').innerHTML=questions.map(q=>'<div class="question-row" data-id="'+esc(q.id||'')+'"><label>问题<input class="question-text" maxlength="100" value="'+esc(q.question)+'" required></label><label>答案<input class="question-answer" type="text" inputmode="text" lang="zh-CN" spellcheck="false" maxlength="64" autocomplete="off" placeholder="'+(q.id?'留空保留原答案':'请输入答案')+'" value="'+esc(q.answer||'')+'"></label><button class="text danger" type="button" data-remove-question>移除</button></div>').join('');
  $('questionRows').querySelectorAll('[data-remove-question]').forEach((b,i)=>b.onclick=()=>{questions=readQuestions();if(questions.length<=1){$('questionError').textContent='请至少保留一个问题';return;}questions.splice(i,1);renderQuestions();});
 }
 $('addQuestion').onclick=()=>{questions=readQuestions();if(questions.length>=20){$('questionError').textContent='最多可以保存 20 个问题';return;}questions.push({id:'',question:'',answer:''});renderQuestions();$('questionRows').lastElementChild.querySelector('input').focus();};
 $('questionCancel').onclick=()=>$('questionEditor').close();
 $('questionEditor').addEventListener('close',()=>{questions=[];$('questionRows').innerHTML='';send('privacyAdminLock').catch(()=>{});});
 $('questionForm').onsubmit=async e=>{
  e.preventDefault();$('questionSave').disabled=true;$('questionError').textContent='';
  try{const result=await send('privacySaveQuestions',{questions:readQuestions()});toast(result.message||'问题库已保存');$('questionEditor').close();}
  catch(err){$('questionError').textContent=err.message;}finally{$('questionSave').disabled=false;}
 };
 window.chrome?.webview?.addEventListener('message',e=>{if(e.data.type==='privacyLocked')purge();});
 return {openAdmin,prepareState,updateControls,previewControl,onLeave:()=>{if(allowHidden||filter==='hidden')lock();}};
})();
