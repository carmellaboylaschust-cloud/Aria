'use strict';
const AriaBackup=(()=>{
 let restorePlan=null,privateMode='export',overview=null;
 async function inspectPublic(){const r=await act('backupInspect');if(r?.planId)review(r);}
 function review(plan){restorePlan=plan;$('backupReviewSummary').textContent=(plan.scope==='private'?'隐藏':'普通')+'皮肤 '+plan.skinCount+' 张 · 约 '+plan.sizeMB+' MB · '+plan.settingsCount+' 项资料';$('backupRestorePreferencesRow').hidden=plan.scope==='private';$('backupRestorePreferences').checked=false;$('backupReviewNote').textContent=plan.scope==='private'?'恢复的皮肤仍进入隐藏列表，当前管理员密码和问题库会保留。':'将合并皮肤、收藏和提示词。内容相同的现有皮肤会保留，编号冲突时保留恢复副本。';$('backupReviewDialog').showModal();}
 async function storage(){
  $('storageRefresh').disabled=true;$('storageStatus').textContent='正在统计 D 盘应用目录…';
  try{const r=await send('storageOverview');overview=r.overview;const max=Math.max(1,...overview.groups.map(g=>g.sizeMB));$('storageGroups').innerHTML=overview.groups.map(g=>'<div class="storage-group"><div><span>'+esc(g.name)+'</span><b>'+esc(g.sizeMB>=1024?(g.sizeMB/1024).toFixed(2)+' GB':g.sizeMB+' MB')+'</b></div><div class="storage-track"><i style="width:'+Math.min(100,Math.max(0,g.sizeMB/max*100))+'%"></i></div></div>').join('');$('storageStatus').textContent='D 盘剩余 '+overview.freeGB+' GB；可清理 '+overview.cleanupCount+' 个过期文件，约 '+overview.cleanupMB+' MB。';$('storageClean').disabled=!overview.cleanupCount;}
  catch(e){$('storageStatus').textContent=e.message;}finally{$('storageRefresh').disabled=false;}
 }
 $('backupExport').onclick=()=>act('backupExport');$('backupInspect').onclick=inspectPublic;$('openBackups').onclick=()=>act('openBackups');
 $('backupReviewCancel').onclick=()=>$('backupReviewDialog').close();$('backupReviewDialog').addEventListener('close',()=>restorePlan=null);
 $('backupRestore').onclick=async()=>{if(!restorePlan)return;const planId=restorePlan.planId,applySettings=$('backupRestorePreferences').checked;$('backupRestore').disabled=true;$('backupReviewCancel').disabled=true;try{const r=await act('backupRestore',{planId,applySettings});if(r)$('backupReviewDialog').close();}finally{$('backupRestore').disabled=false;$('backupReviewCancel').disabled=false;}};
 function privateDialog(mode){
  if(!state.hiddenUnlocked){toast('先进入隐藏皮肤回答问题，再打开管理员与问题库管理');return;}
  privateMode=mode;$('backupPrivateTitle').textContent=mode==='export'?'加密备份隐藏收藏':'恢复隐藏收藏';$('backupPrivateConfirmRow').hidden=mode!=='export';$('backupPrivatePassword').minLength=mode==='export'?8:1;$('backupPrivateConfirmation').required=mode==='export';$('backupPrivateError').textContent='';$('backupPrivateDialog').showModal();$('backupPrivatePassword').focus();
 }
 $('backupPrivateExport').onclick=()=>privateDialog('export');$('backupPrivateInspect').onclick=()=>privateDialog('inspect');$('backupPrivateCancel').onclick=()=>$('backupPrivateDialog').close();
 $('backupPrivateDialog').addEventListener('close',()=>{$('backupPrivatePassword').value='';$('backupPrivateConfirmation').value='';});
 $('backupPrivateForm').onsubmit=async e=>{
  e.preventDefault();const password=$('backupPrivatePassword').value,confirmation=$('backupPrivateConfirmation').value;$('backupPrivateError').textContent='';
  if(privateMode==='export'&&password!==confirmation){$('backupPrivateError').textContent='两次备份密码不一致';return;}
  $('backupPrivatePassword').value='';$('backupPrivateConfirmation').value='';$('backupPrivateSubmit').disabled=true;
  try{const r=await send(privateMode==='export'?'backupPrivateExport':'backupPrivateInspect',{password,confirmation});$('backupPrivateDialog').close();if(r.planId)review(r);else if(r.message)toast(r.message);}
  catch(err){$('backupPrivateError').textContent=err.message;$('backupPrivatePassword').focus();}finally{$('backupPrivateSubmit').disabled=false;}
 };
 function closePrivate(){if($('backupPrivateDialog').open)$('backupPrivateDialog').close();if(restorePlan?.scope==='private'&&$('backupReviewDialog').open)$('backupReviewDialog').close();}
 $('questionEditor').addEventListener('close',closePrivate);window.chrome?.webview?.addEventListener('message',e=>{if(e.data.type==='privacyLocked')closePrivate();});
 $('storageRefresh').onclick=storage;$('storageClean').onclick=()=>{if(!overview?.cleanupCount)return;$('storageCleanSummary').textContent='清理 '+overview.cleanupCount+' 个过期临时文件和失效缩略图，预计释放 '+overview.cleanupMB+' MB。';$('storageCleanDialog').showModal();};
 $('storageCleanCancel').onclick=()=>$('storageCleanDialog').close();$('storageCleanConfirm').onclick=async()=>{if(!overview)return;$('storageCleanConfirm').disabled=true;try{const r=await act('storageCleanup',{planId:overview.cleanupPlanId});if(r){$('storageCleanDialog').close();await storage();}}finally{$('storageCleanConfirm').disabled=false;}};
 return {storage};
})();