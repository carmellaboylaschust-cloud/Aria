'use strict';
const AriaWuwaImages=(()=>{
 let generation=0,busy=new Set(),saved=new Map();
 function render(items){
  $('wuwaImageGrid').innerHTML=items.map(i=>'<article class="download-card"><a class="wuwa-image-art" href="#" data-wuwa-preview="'+esc(i.id)+'" aria-label="预览 '+esc(i.title)+'"><img src="'+esc(i.preview)+'" alt="" loading="lazy" referrerpolicy="no-referrer"></a><div class="download-info"><h3>'+esc(i.title)+'</h3><p>'+((i.width&&i.height)?esc(i.width+' × '+i.height):'网页提供的原图')+'</p><button class="soft" data-wuwa-save="'+esc(i.id)+'">保存并加入皮肤</button></div></article>').join('');
  $('wuwaImageGrid').querySelectorAll('[data-wuwa-preview]').forEach(b=>b.onclick=e=>{e.preventDefault();const item=items.find(i=>i.id===b.dataset.wuwaPreview);$('wuwaImagePreviewName').textContent=item.title;$('wuwaImagePreviewArt').src=item.preview;$('wuwaImagePreview').showModal();});
  $('wuwaImageGrid').querySelectorAll('[data-wuwa-save]').forEach(b=>b.onclick=async()=>{
   const id=b.dataset.wuwaSave;if(busy.has(id))return;
   if(saved.has(id)){$('wuwaImageDialog').close();go('library');if(saved.get(id))openPreview(saved.get(id));return;}
   busy.add(id);b.disabled=true;b.textContent='正在保存…';const r=await act('wuwaSaveImage',{imageId:id});busy.delete(id);
   if(!b.isConnected)return;b.disabled=false;b.textContent=r?'已保存 · 查看皮肤':'重试保存';if(r)saved.set(id,r.themeId||'');
  });
 }
 async function open(){
  const mine=++generation;saved.clear();$('wuwaImageGrid').innerHTML='';$('wuwaImageNotice').textContent='正在读取当前网页中的图片…';$('wuwaImageDialog').showModal();
  try{const r=await send('wuwaImages');if(mine!==generation)return;render(r.images||[]);$('wuwaImageNotice').textContent=r.images?.length?'选择图片保存；网页使用缩略图时，请先打开原图页面再读取。':'本页尚未找到大图。请先打开壁纸详情，或点击网站自己的下载按钮。';}
  catch(e){if(mine===generation)$('wuwaImageNotice').textContent=e.message;}
 }
 $('wuwaSavePage').onclick=open;$('wuwaImageRefresh').onclick=()=>{if($('wuwaImageDialog').open)$('wuwaImageDialog').close();open();};
 $('wuwaImageClose').onclick=()=>$('wuwaImageDialog').close();
 $('wuwaImageDialog').addEventListener('close',()=>{generation++;$('wuwaImageGrid').innerHTML='';if($('wuwaImagePreview').open)$('wuwaImagePreview').close();send('wuwaImagePickerClose').catch(()=>{});});
 $('wuwaImagePreviewClose').onclick=()=>$('wuwaImagePreview').close();$('wuwaImagePreview').addEventListener('close',()=>$('wuwaImagePreviewArt').removeAttribute('src'));
 return {open};
})();