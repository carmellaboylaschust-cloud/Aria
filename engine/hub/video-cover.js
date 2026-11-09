'use strict';
const AriaVideoCover=(()=>{
 const row=document.createElement('div');row.className='display-control video-cover-controls';row.hidden=true;
 const capture=document.createElement('button');capture.className='soft';capture.textContent='用当前画面作封面';
 const reset=document.createElement('button');reset.className='text';reset.textContent='恢复自动封面';
 row.append(capture,reset);$('videoAudioRow').after(row);
 let busy=false,video=null;
 function sync(){
  video=$('previewMedia').querySelector('video');row.hidden=!video;
  capture.disabled=busy||!video||video.readyState<2||video.seeking||!Number.isFinite(video.currentTime);
  reset.disabled=busy||!video;
 }
 async function save(automatic){
  if(busy||!selected||!video||selected.kind!=='video')return;
  const themeId=selected.id,time=video.currentTime;
  if(!automatic&&(!Number.isFinite(time)||time<0||video.readyState<2||video.seeking))return;
  busy=true;sync();
  try{const r=await send(automatic?'resetVideoCover':'videoCover',automatic?{themeId}:{themeId,time});toast(r.message||(automatic?'已恢复自动封面':'已保存当前画面为封面'));}
  catch(e){toast(e.message);}
  finally{busy=false;sync();}
 }
 capture.onclick=()=>save(false);reset.onclick=()=>save(true);
 new MutationObserver(()=>{
  const next=$('previewMedia').querySelector('video');
  if(next&&next!==video)for(const name of ['loadeddata','seeking','seeked','error','emptied'])next.addEventListener(name,sync);
  sync();
 }).observe($('previewMedia'),{childList:true});
 $('preview').addEventListener('close',sync);
 return {sync};
})();
