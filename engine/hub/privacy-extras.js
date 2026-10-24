'use strict';
const AriaPrivacyExtras=(()=>{
 let signature='',playbackSignature='';
 function render(){
  const audio=state.playbackSettings?.audioEnabled===true;for(const id of ['videoAudio','settingsVideoAudio'])if(document.activeElement!==$(id))$(id).checked=audio;
  const playback=state.playbackSettings?.mode||'normal';if(playback!==playbackSignature){playbackSignature=playback;$('playbackMode').value=playback;}
  const value=state.privacySettings?.safeThemeId||'',next=JSON.stringify([state.themes.map(t=>[t.id,t.name]),value]);if(next===signature)return;signature=next;
  $('privacySafeTheme').innerHTML='<option value="">最近使用的普通皮肤</option>'+state.themes.map(t=>'<option value="'+esc(t.id)+'">'+esc(t.name)+'</option>').join('');$('privacySafeTheme').value=value;
 }
 async function setAudio(input){const enabled=input.checked;for(const id of ['videoAudio','settingsVideoAudio'])$(id).disabled=true;try{const result=await act('saveVideoAudio',{enabled});if(result){state.playbackSettings={...state.playbackSettings,audioEnabled:enabled};}else input.checked=!enabled;}finally{for(const id of ['videoAudio','settingsVideoAudio'])$(id).disabled=false;render();}}
 $('videoAudio').onchange=()=>setAudio($('videoAudio'));$('settingsVideoAudio').onchange=()=>setAudio($('settingsVideoAudio'));
 $('savePlaybackSettings').onclick=()=>act('savePlaybackSettings',{mode:$('playbackMode').value});
 $('privacyMode').onclick=()=>act('privacyMode');
 $('savePrivacySettings').onclick=()=>act('savePrivacySettings',{themeId:$('privacySafeTheme').value});
 $('privacyAdminSettings').onclick=()=>AriaPrivacy.openAdmin();
 $('openPasswordChange').onclick=()=>{$('passwordChangeError').textContent='';$('passwordChangeDialog').showModal();$('passwordCurrent').focus();};
 $('passwordChangeCancel').onclick=()=>$('passwordChangeDialog').close();
 $('passwordChangeDialog').addEventListener('close',()=>{for(const id of ['passwordCurrent','passwordNew','passwordConfirm'])$(id).value='';});
 $('questionEditor').addEventListener('close',()=>{if($('passwordChangeDialog').open)$('passwordChangeDialog').close();});
 $('passwordChangeForm').onsubmit=async e=>{
  e.preventDefault();const currentPassword=$('passwordCurrent').value,newPassword=$('passwordNew').value,confirmation=$('passwordConfirm').value;$('passwordChangeError').textContent='';
  if(newPassword!==confirmation){$('passwordChangeError').textContent='两次新密码不一致';return;}
  for(const id of ['passwordCurrent','passwordNew','passwordConfirm'])$(id).value='';
  $('passwordChangeSave').disabled=true;
  try{const r=await send('privacyChangePassword',{currentPassword,newPassword,confirmation});$('passwordChangeDialog').close();$('questionEditor').close();toast(r.message||'管理员密码已更新，请重新验证');}
  catch(err){$('passwordChangeError').textContent=err.message;$('passwordCurrent').focus();}finally{$('passwordChangeSave').disabled=false;}
 };
 return {render};
})();