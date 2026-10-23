'use strict';
const AriaDownloads=(()=>{
 let items=[],kind='all',selection=new Set(),loading=false;
 const label=t=>t==='video'?'视频':t==='scene'?'Scene 场景':t==='web'?'Web 网页':'其他类型';
 function visible(){const q=$('downloadedSearch').value.trim().toLowerCase();return items.filter(i=>(!q||(i.name+' '+i.id).toLowerCase().includes(q))&&(kind==='all'||kind===i.type||kind==='imported'&&i.themeId));}
 function eligible(i){return !i.reason&&!i.themeId&&!['queued','starting','recording','finalizing','waiting-download'].includes(i.jobStatus);}
 function render(){
  const list=visible();$('downloadedCount').textContent=items.length+' 张本地壁纸';$('downloadedMatch').textContent=list.length+' 个结果';
  $('downloadedGrid').innerHTML=list.map(i=>'<article class="download-card"><button class="download-art" data-dl-preview="'+esc(i.id)+'" aria-label="预览 '+esc(i.name)+'">'+(i.preview?'<img src="'+esc(i.preview)+'" alt="" loading="lazy">':'<span class="download-no-preview">暂无预览图</span>')+'<span class="download-type">'+esc(label(i.type))+'</span></button><div class="download-info"><h3 title="'+esc(i.name)+'">'+esc(i.name)+'</h3><p>'+esc(i.reason||(i.themeId?'已加入我的皮肤':status[i.jobStatus]||'已下载 · 可以导入'))+'</p><div class="row">'+(eligible(i)?'<label class="download-select"><input type="checkbox" data-dl-check="'+esc(i.id)+'" '+(selection.has(i.id)?'checked':'')+'>选择</label>':'<span class="download-meta">'+esc(i.id)+'</span>')+(i.themeId?'<button class="soft" data-dl-open="'+esc(i.themeId)+'">查看皮肤</button>':eligible(i)?'<button class="soft" data-dl-import="'+esc(i.id)+'">'+(['scene','web'].includes(i.type)?'排队录制':'导入皮肤')+'</button>':'')+'</div></div></article>').join('');
  $('downloadedEmpty').hidden=list.length>0;$('downloadedImport').disabled=!selection.size||loading;$('downloadedImport').textContent=selection.size?'导入已选 '+selection.size+' 张':'导入已选';
  $('downloadedGrid').querySelectorAll('[data-dl-check]').forEach(b=>b.onchange=()=>{b.checked?selection.add(b.dataset.dlCheck):selection.delete(b.dataset.dlCheck);render();});
  $('downloadedGrid').querySelectorAll('[data-dl-import]').forEach(b=>b.onclick=()=>importItems([b.dataset.dlImport]));
  $('downloadedGrid').querySelectorAll('[data-dl-open]').forEach(b=>b.onclick=()=>{$('downloadedDialog').close();go('library');openPreview(b.dataset.dlOpen);});
  $('downloadedGrid').querySelectorAll('[data-dl-preview]').forEach(b=>b.onclick=()=>preview(b.dataset.dlPreview));
 }
 async function refresh(){
  if(loading)return;loading=true;$('downloadedRefresh').disabled=true;$('downloadedNotice').textContent='正在读取本地壁纸…';
  try{const r=await send('browseDownloaded');items=r.items||[];selection=new Set([...selection].filter(id=>items.some(i=>i.id===id&&eligible(i))));$('downloadedNotice').textContent='视频直接入库；Scene / Web 后台录制后入库。';render();}
  catch(e){$('downloadedNotice').textContent=e.message;}finally{loading=false;$('downloadedRefresh').disabled=false;render();}
 }
 async function open(){$('downloadedDialog').showModal();await refresh();}
 async function importItems(ids){
  if(loading||!ids.length)return;loading=true;render();
  const result=await act('workshopBatch',{workshopIds:ids});loading=false;if(result){ids.forEach(id=>selection.delete(id));await refresh();}else render();
 }
 function preview(id){const i=items.find(i=>i.id===id);if(!i)return;$('downloadedPreviewName').textContent=i.name;$('downloadedPreviewImage').innerHTML=i.preview?'<img src="'+esc(i.preview)+'" alt="">':'<p>这张壁纸没有本地预览图</p>';$('downloadedPreviewNote').textContent=i.reason||label(i.type)+' · '+(i.themeId?'已在皮肤库':'可加入后台导入任务');$('downloadedPreview').showModal();}
 $('browseDownloaded').onclick=open;
 $('downloadedClose').onclick=()=>$('downloadedDialog').close();
 $('downloadedDialog').addEventListener('close',()=>{if($('downloadedPreview').open)$('downloadedPreview').close();$('downloadedGrid').innerHTML='';items=[];selection.clear();send('downloadedClose').catch(()=>{});});
 $('downloadedPreviewClose').onclick=()=>$('downloadedPreview').close();
 $('downloadedPreview').addEventListener('close',()=>$('downloadedPreviewImage').innerHTML='');
 $('downloadedRefresh').onclick=refresh;$('downloadedSearch').oninput=render;
 $('downloadedFilters').onclick=e=>{const b=e.target.closest('[data-dl-filter]');if(!b)return;kind=b.dataset.dlFilter;$('downloadedFilters').querySelectorAll('button').forEach(x=>x.classList.toggle('selected',x===b));render();};
 $('downloadedSelect').onclick=()=>{const ids=visible().filter(eligible).map(i=>i.id),all=ids.length&&ids.every(id=>selection.has(id));ids.forEach(id=>all?selection.delete(id):selection.add(id));render();};
 $('downloadedImport').onclick=()=>importItems([...selection]);$('downloadedJobs').onclick=()=>{$('downloadedDialog').close();go('jobs');};
 return {open};
})();
