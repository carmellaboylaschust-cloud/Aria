'use strict';
const AriaLibrary=(()=>{
 let ids=[],batch=false;
 const pool=()=>libraryPool();
 const group=t=>String(t.group||'').trim();
 const batchFields=[['Group','libraryEditGroup'],['Tags','libraryTags']];
 for(const [name,inputId] of batchFields){
  const select=document.createElement('select');select.id='library'+name+'Mode';select.setAttribute('aria-label',name==='Group'?'批量分组操作':'批量标签操作');
  select.innerHTML='<option value="keep">保留各自原值</option><option value="replace">统一修改</option><option value="clear">清空这一项</option>';
  select.hidden=true;select.style.marginBottom='8px';$(inputId).before(select);
  select.onchange=()=>{$(inputId).disabled=batch&&select.value!=='replace';if(select.value==='replace')$(inputId).focus();};
 }
 function batchModes(){for(const [name,inputId] of batchFields){const mode=$('library'+name+'Mode');mode.hidden=!batch;mode.value='keep';$(inputId).disabled=batch;}}

 function filters(){
  const value=$('libraryGroup').value,groups=[...new Set(pool().map(group).filter(Boolean))].sort((a,b)=>a.localeCompare(b,'zh-CN'));
  const signature=JSON.stringify(groups);if($('libraryGroup').dataset.signature===signature)return;
  $('libraryGroup').dataset.signature=signature;$('libraryGroup').innerHTML='<option value="">全部分组</option><option value="__ungrouped">未分组</option>'+groups.map(g=>'<option value="'+esc(g)+'">'+esc(g)+'</option>').join('');
  $('libraryGroup').value=[...$('libraryGroup').options].some(o=>o.value===value)?value:'';
 }
 function query(list){
  filters();const text=$('search').value.trim().toLowerCase(),g=$('libraryGroup').value,mode=$('librarySort').value;
  const found=list.filter(t=>(!text||[t.name,t.group,...(t.tags||[])].join(' ').toLowerCase().includes(text))&&(!g||(g==='__ungrouped'?!group(t):group(t)===g)));
  return [...found].sort((a,b)=>mode==='name'?a.name.localeCompare(b.name,'zh-CN'):mode==='size'?b.sizeMB-a.sizeMB:mode==='recent'?(Date.parse(b.lastUsed)||0)-(Date.parse(a.lastUsed)||0)||(Date.parse(b.addedAt)||0)-(Date.parse(a.addedAt)||0):(Date.parse(b.addedAt)||0)-(Date.parse(a.addedAt)||0));
 }
 function open(values,isBatch=false){
  ids=values.filter(id=>pool().some(t=>t.id===id));if(!ids.length)return;batch=isBatch;
  const items=pool().filter(t=>ids.includes(t.id)),first=items[0];$('libraryEditTitle').textContent=batch?'整理已选 '+ids.length+' 张皮肤':'整理这份心动';
  $('libraryNameRow').hidden=batch;$('libraryName').required=!batch;$('libraryName').value=batch?'':first.name;
  $('libraryEditGroup').value=items.every(t=>group(t)===group(first))?group(first):'';$('libraryTags').value=items.every(t=>JSON.stringify(t.tags||[])===JSON.stringify(first.tags||[]))?(first.tags||[]).join('，'):'';
  $('libraryGroupNames').innerHTML=[...new Set(pool().map(group).filter(Boolean))].map(g=>'<option value="'+esc(g)+'"></option>').join('');
  batchModes();$('libraryEditNote').textContent=batch?'分别选择要修改的分组或标签，其余资料会保留。':'';$('libraryEditNote').hidden=!batch;
  $('libraryEditError').textContent='';$('libraryEditDialog').showModal();setTimeout(()=>$(batch?'libraryGroupMode':'libraryName').focus(),0);
 }
 $('editLibrarySelected').onclick=()=>{if(selected)open([selected.id]);};$('batchLibraryEdit').onclick=()=>open([...uninstallSelection],true);
 $('libraryEditCancel').onclick=()=>$('libraryEditDialog').close();
 $('libraryEditDialog').addEventListener('close',()=>{ids=[];$('libraryName').value='';$('libraryEditGroup').value='';$('libraryTags').value='';$('libraryGroupNames').innerHTML='';});
 $('libraryEditForm').onsubmit=async e=>{
  e.preventDefault();if(!ids.length)return;
  const themeIds=[...ids],name=$('libraryName').value.trim(),group=$('libraryEditGroup').value.trim(),tags=$('libraryTags').value.split(/[,，]/).map(t=>t.trim()).filter(Boolean);
  const update={themeIds,rename:!batch};if(!batch)update.name=name;
  const groupMode=batch?$('libraryGroupMode').value:'replace',tagsMode=batch?$('libraryTagsMode').value:'replace';
  if(groupMode!=='keep')update.group=groupMode==='clear'?'':group;
  if(tagsMode!=='keep')update.tags=tagsMode==='clear'?[]:tags;
  $('libraryEditSave').disabled=true;$('libraryEditError').textContent='';
  try{const r=await send('saveLibraryMeta',update);for(const t of [...state.themes,...(state.hiddenThemes||[])])if(themeIds.includes(t.id)){if(!batch)t.name=name;if(Object.hasOwn(update,'group'))t.group=update.group;if(Object.hasOwn(update,'tags'))t.tags=[...new Set(update.tags)];}
   if(selected&&themeIds.includes(selected.id))$('previewName').textContent=selected.name;
   lastSignature='';renderLibrary();renderRecent();renderCurrent();$('libraryEditDialog').close();toast(r.message||'皮肤资料已保存');
  }catch(err){$('libraryEditError').textContent=err.message;}finally{$('libraryEditSave').disabled=false;}
 };
 $('libraryGroup').onchange=renderLibrary;$('librarySort').onchange=()=>{localStorage.setItem('ariaLibrarySort',$('librarySort').value);renderLibrary();};
 const sort=localStorage.getItem('ariaLibrarySort');if(['added','recent','name','size'].includes(sort))$('librarySort').value=sort;
 return {query,open,lock(){if($('libraryEditDialog').open)$('libraryEditDialog').close();}};
})();