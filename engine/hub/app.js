'use strict';
const $=id=>document.getElementById(id);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const paths={spark:'M12 3l2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5L12 3z M20 2v4 M18 4h4',image:'M4 4h16v16H4z M4 16l5-5 4 4 3-3 4 4 M14 8h.01',globe:'M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0z M3 12h18 M12 3c5 5 5 13 0 18-5-5-5-13 0-18',list:'M9 6h12 M9 12h12 M9 18h12 M3 6h1 M3 12h1 M3 18h1',book:'M12 6c-4-3-8-2-9-1v14c3-2 6-2 9 0 3-2 6-2 9 0V5c-3-2-6-2-9 1z M12 6v13',sliders:'M6 3v5 M6 12v9 M18 3v9 M18 16v5 M3 8h6v4H3z M15 12h6v4h-6z',folder:'M3 6h7l2 3h9v11H3V6z',play:'M8 4l12 8-12 8V4z',plus:'M12 4v16 M4 12h16'};
function icons(){document.querySelectorAll('i[data-icon]').forEach(el=>el.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="'+(paths[el.dataset.icon]||paths.spark)+'"/></svg>');} icons();
let state={themes:[],jobs:[],heroes:[],prompts:[],favorites:[],activeId:'',policy:{videoMaxMB:256,sceneMaxMB:512}};
let page='home',filter='all',selected=null,hero=0,heroPaused=false,launchBusy=false,lastSignature='',promptId=null;
let managing=false,uninstallBusy=false;const uninstallSelection=new Set();let uninstallReview=[];
const pending=new Map();let requestId=0;
function send(action,data={}){
 if(!window.chrome?.webview){return Promise.resolve({ok:true});}
 const id=++requestId;
 return new Promise((resolve,reject)=>{
  const timer=setTimeout(()=>{pending.delete(id);reject(new Error('操作超时，请稍后重试。'));},90000);
  pending.set(id,{resolve,reject,timer});
  window.chrome.webview.postMessage({id,action,...data});
 });
}
window.chrome?.webview?.addEventListener('message',event=>{
 const msg=event.data;
 if(msg.type==='notice'){toast(msg.message);return;}
 if(msg.type==='jobCompleted'){const open=()=>{$('jobCompletionAction').hidden=true;go('library');if(state.themes.some(t=>t.id===msg.themeId))openPreview(msg.themeId);};$('jobCompletionAction').hidden=false;$('jobCompletionAction').onclick=open;toast(msg.name+' · 已加入我的皮肤',open);return;}
 if(msg.type==='state'){acceptState(msg.data);return;}
 if(msg.type==='steamSubscriptionQueued'){toast('已加入导入队列',()=>go('jobs'),'查看任务');return;}
 if(msg.type==='steamHealth'){$('steamMessage').textContent=msg.message;$('steamHealth').classList.toggle('error',!!msg.error);return;}
 if(msg.type==='wuwaHealth'){$('wuwaMessage').textContent=msg.message;$('wuwaHealth').classList.toggle('error',!!msg.error);return;}
 if(msg.type==='wuwaUrl'){$('wuwaUrl').value=msg.url;return;}
 if(msg.type==='steamUrl'){$('steamUrl').value=msg.url;return;}
 if(msg.type==='launchProgress'){$('appStatus').textContent=msg.message;return;}
 if(msg.type==='launchDone'){launchBusy=false;setLaunchBusy(false);toast(msg.message);return;}
 const req=pending.get(msg.id);
 if(req){clearTimeout(req.timer);pending.delete(msg.id);msg.ok?req.resolve(msg):req.reject(new Error(msg.error||'操作未完成'));}
});
let toastTimer;function toast(text,action=null,actionLabel='查看皮肤'){$('toast').textContent=text;if(action){const button=document.createElement('button');button.className='toast-link';button.textContent=actionLabel;button.onclick=()=>{action();$('toast').classList.remove('show');};$('toast').append(button);}$('toast').classList.add('show');clearTimeout(toastTimer);toastTimer=setTimeout(()=>$('toast').classList.remove('show'),action?9000:5500);}
async function act(action,data={}){try{const result=await send(action,data);if(result.message)toast(result.message);return result;}catch(e){toast(e.message);return null;}}
const names={home:['发现灵感','给今天，换一份心动'],library:['我的皮肤','把喜欢的风景，收进小世界'],workshop:['Steam 创意工坊','下一份心动，正在路上'],wuwa:['鸣潮专区','走进鸣潮的壁纸小世界'],jobs:['转换任务','让心动，慢慢变得清晰'],prompts:['提示词小屋','和灵感一起，开始工作'],settings:['偏好与存储','把你的小世界，照顾妥当']};
function go(next){
 if(page==='library'&&next!=='library'&&typeof AriaPrivacy!=='undefined')AriaPrivacy.onLeave();
 page=next;document.body.dataset.currentPage=page;document.querySelectorAll('.page').forEach(el=>el.classList.toggle('active',el.id===page));
 document.querySelectorAll('nav button[data-page]').forEach(el=>el.classList.toggle('active',el.dataset.page===page));
 $('breadcrumb').textContent='Aria / '+names[page][0];$('pageTitle').innerHTML=esc(names[page][1])+'<span>✦</span>';
 if(page==='workshop'){send('workshop',{visible:true}).then(()=>setTimeout(syncBounds,80)).catch(e=>toast(e.message));}else send('workshop',{visible:false}).catch(()=>{});
 if(page==='wuwa'){send('wuwa',{visible:true}).then(()=>setTimeout(syncBounds,80)).catch(e=>toast(e.message));}else send('wuwa',{visible:false}).catch(()=>{});
 if(page==='prompts'){if(typeof AriaPrompts!=='undefined')AriaPrompts.enter();else if(!promptId&&state.prompts.length)editPrompt(state.prompts[0].id);}
 renderJobs();window.scrollTo({top:0,behavior:'instant'});
}
document.querySelectorAll('[data-page]').forEach(b=>b.onclick=()=>go(b.dataset.page));
document.querySelectorAll('[data-go]').forEach(b=>b.onclick=()=>go(b.dataset.go));
function acceptState(data){
 const first=!lastSignature;
 if(typeof AriaPrivacy!=='undefined')data=AriaPrivacy.prepareState(data);
 state={...state,...data};
 if(typeof AriaConnection!=='undefined')AriaConnection.render(state.desktopConnection);
 if(typeof AriaPrivacyExtras!=='undefined')AriaPrivacyExtras.render();
 if(state.windowSettings){$('windowSizeLabel').textContent=state.windowSettings.state==='maximized'?'已最大化':state.windowSettings.width+' × '+state.windowSettings.height;}
 $('libraryCount').textContent=state.themes.length;
 const busy=state.jobs.filter(j=>['queued','starting','recording','finalizing','waiting-download'].includes(j.status));
 $('jobCount').textContent=busy.length;$('queueSummary').textContent=busy.length?'有 '+busy.length+' 个任务正在准备你的背景':'暂无进行中的任务';
 $('freeSpace').textContent='剩余 '+state.freeGB+' GB · D 盘';$('appStatus').textContent=launchBusy?'正在启动桌面端…':'本地皮肤库已连接 · '+state.themes.length+' 张背景';
 if(first||JSON.stringify(state.heroes)!==lastHeroes){setupHeroes();}
 const signature=JSON.stringify([state.hiddenThemes,state.hiddenUnlocked])+JSON.stringify(state.themes)+state.activeId+state.favorites.join('|');
 if(signature!==lastSignature){lastSignature=signature;renderLibrary();renderRecent();renderCurrent();}
 renderJobs();renderPrompts();if(selected){selected=[...state.themes,...(state.hiddenThemes||[])].find(t=>t.id===selected.id)||null;}if(selected){$('favoriteSelected').textContent=state.favorites.includes(selected.id)?'♥ 已收藏':'♡ 收藏';}
 if(first){$('rememberWindow').checked=state.windowSettings?.remember!==false;$('videoLimit').value=state.policy.videoMaxMB;$('sceneLimit').value=state.policy.sceneMaxMB;$('autoWorkshop').checked=state.policy.autoImportWorkshop!==false;}
}
function card(t,manage=false){
 const fav=state.favorites.includes(t.id),active=t.id===state.activeId;
 const art=t.thumbnail||t.url;
 const media=t.kind==='video'&&!t.thumbnail?'<video src="'+esc(art)+'" muted preload="metadata"></video>':'<img src="'+esc(art)+'" loading="lazy" alt="">';
 return '<button class="card '+(manage?'manage-card ':'')+(manage&&uninstallSelection.has(t.id)?'chosen':'')+'" data-theme="'+esc(t.id)+'" '+(manage?'aria-pressed="'+uninstallSelection.has(t.id)+'" ':'')+(manage&&active?'disabled aria-label="当前正在使用，请先切换背景"':'')+'><div class="card-cover">'+media+'<span class="tag">'+esc(t.kind==='video'?'视频 · 静音循环':t.kind==='gif'?'动图':'静态壁纸')+'</span><span class="heart">'+(manage?(active?'使用中':(uninstallSelection.has(t.id)?'✓':'○')):(fav?'♥':'♡'))+'</span></div><div class="card-info"><strong>'+esc(t.name)+'</strong><p><span>'+esc(t.sizeMB)+' MB · '+esc(t.dimensions||'本地收藏')+'</span><span class="'+(active?'active-tag':'')+'">'+(active?'✓ 正在陪伴':'预览 ↗')+'</span></p></div></button>';
}
function wireCards(container){container.querySelectorAll('[data-theme]').forEach(el=>el.onclick=()=>{if(container.id==='skinGrid'&&managing){const id=el.dataset.theme;if(id===state.activeId)return;uninstallSelection.has(id)?uninstallSelection.delete(id):uninstallSelection.add(id);renderLibrary();}else openPreview(el.dataset.theme);});}
function libraryPool(){return filter==='hidden'?(state.hiddenUnlocked?state.hiddenThemes||[]:[]):state.themes;}
function renderLibrary(){
 const text=$('search').value.toLowerCase();
 let all=libraryPool().filter(t=>filter==='hidden'||filter==='all'||filter==='favorite'&&state.favorites.includes(t.id)||filter==='image'&&t.kind==='image'||filter==='animated'&&t.kind!=='image');
 all=typeof AriaLibrary!=='undefined'?AriaLibrary.query(all):all.filter(t=>t.name.toLowerCase().includes(text));
 for(const id of [...uninstallSelection])if(!libraryPool().some(t=>t.id===id)||id===state.activeId)uninstallSelection.delete(id);
 $('skinGrid').innerHTML=all.map(t=>card(t,managing)).join('');$('emptyLibrary').hidden=all.length>0;wireCards($('skinGrid'));
 $('manageBar').hidden=!managing;$('manageSkins').textContent=managing?'完成管理':'管理皮肤';$('manageSkins').setAttribute('aria-pressed',String(managing));
 $('selectedCount').textContent='已选择 '+uninstallSelection.size+' 张';$('uninstallSkins').disabled=uninstallBusy||!uninstallSelection.size;if($('batchLibraryEdit'))$('batchLibraryEdit').disabled=uninstallBusy||!uninstallSelection.size;
 if(typeof AriaPrivacy!=='undefined')AriaPrivacy.updateControls();
}
function renderRecent(){const recent=[...state.themes].filter(t=>!t.id.startsWith('preset')).sort((a,b)=>(Date.parse(b.lastUsed)||0)-(Date.parse(a.lastUsed)||0)||(Date.parse(b.addedAt)||0)-(Date.parse(a.addedAt)||0)).slice(0,3);$('recentGrid').innerHTML=recent.map(t=>card(t,false)).join('');wireCards($('recentGrid'));}
function renderCurrent(){
 const t=state.themes.find(x=>x.id===state.activeId);
 $('currentSkin').innerHTML=t?'<img src="'+esc(t.thumbnail||t.url)+'" alt=""><div><strong>'+esc(t.name)+'</strong></div>':'<div><strong>还没有选择皮肤</strong><p>去收藏里挑一张吧 ♡</p></div>';
}
$('manageSkins').onclick=()=>{managing=!managing;if(!managing)uninstallSelection.clear();renderLibrary();};
$('selectVisible').onclick=()=>{const ids=[...$('skinGrid').querySelectorAll('[data-theme]:not(:disabled)')].map(b=>b.dataset.theme);const all=ids.length&&ids.every(id=>uninstallSelection.has(id));ids.forEach(id=>all?uninstallSelection.delete(id):uninstallSelection.add(id));renderLibrary();};
$('uninstallSkins').onclick=()=>{
 uninstallReview=libraryPool().filter(t=>uninstallSelection.has(t.id)&&t.id!==state.activeId);if(!uninstallReview.length)return;
 $('uninstallSummary').textContent='已选择 '+uninstallReview.length+' 张，皮肤库副本共约 '+uninstallReview.reduce((sum,t)=>sum+t.sizeMB,0).toFixed(1)+' MB。';
 $('uninstallNames').innerHTML=uninstallReview.map(t=>'<li>'+esc(t.name)+'</li>').join('');$('uninstallDialog').showModal();
};
$('cancelUninstall').onclick=()=>$('uninstallDialog').close();
$('confirmUninstall').onclick=async()=>{
 if(uninstallBusy)return;uninstallBusy=true;$('confirmUninstall').disabled=true;$('cancelUninstall').disabled=true;
 try{const result=await act('uninstallThemes',{themeIds:uninstallReview.map(t=>t.id)});
 if(result){const removed=new Set(result.removedIds||[]);state.themes=state.themes.filter(t=>!removed.has(t.id));state.hiddenThemes=(state.hiddenThemes||[]).filter(t=>!removed.has(t.id));state.favorites=state.favorites.filter(id=>!removed.has(id));removed.forEach(id=>uninstallSelection.delete(id));lastSignature='';renderLibrary();renderRecent();renderCurrent();$('libraryCount').textContent=state.themes.length;$('uninstallDialog').close();}}
 finally{uninstallBusy=false;$('confirmUninstall').disabled=false;$('cancelUninstall').disabled=false;renderLibrary();}
};
$('search').oninput=renderLibrary;
$('filters').onclick=e=>{const b=e.target.closest('[data-filter]');if(!b)return;filter=b.dataset.filter;document.querySelectorAll('[data-filter]').forEach(el=>el.classList.toggle('selected',el===b));renderLibrary();};
function openPreview(id){
 selected=[...state.themes,...(state.hiddenUnlocked?state.hiddenThemes||[]:[])].find(t=>t.id===id);if(!selected)return;
 $('displayMode').value=selected.displayMode||'cover';
 $('resolutionHint').textContent=selected.dimensions?'原素材 '+selected.dimensions:'';
 $('previewName').textContent=selected.name;$('previewMedia').innerHTML=selected.kind==='video'?'<video src="'+esc(selected.url)+'" controls muted autoplay loop playsinline></video>':'<img src="'+esc(selected.url)+'" alt="">';
 $('opacity').value=selected.opacity??30;$('opacityValue').textContent=(selected.opacity??30)+'%';
 $('recordSelected').hidden=!selected.sceneProject;$('favoriteSelected').textContent=state.favorites.includes(id)?'♥ 已收藏':'♡ 收藏';if(typeof AriaPrivacy!=='undefined')AriaPrivacy.previewControl();$('preview').showModal();
}
function clearPreview(){$('previewMedia').innerHTML='';$('previewName').textContent='';$('resolutionHint').textContent='';selected=null;}
function closePreview(){$('preview').close();clearPreview();}
$('closePreview').onclick=closePreview;$('preview').addEventListener('close',clearPreview);
$('preview').onclick=e=>{if(e.target===$('preview')){const r=$('preview').getBoundingClientRect();if(e.clientX<r.x||e.clientX>r.right||e.clientY<r.y||e.clientY>r.bottom)closePreview();}};
$('displayMode').onchange=async()=>{if(!selected)return;const id=selected.id,mode=$('displayMode').value;const result=await act('displayMode',{themeId:id,mode});if(result){selected.displayMode=mode;}};
$('favoriteSelected').onclick=async()=>{if(!selected)return;await act('favorite',{themeId:selected.id});};
let opacityTimer;
$('opacity').oninput=()=>{$('opacityValue').textContent=$('opacity').value+'%';clearTimeout(opacityTimer);const id=selected?.id,value=Number($('opacity').value);opacityTimer=setTimeout(()=>{if(id)act('opacity',{themeId:id,value});},180);};
$('resetOpacity').onclick=()=>{if(selected){clearTimeout(opacityTimer);$('opacity').value=30;$('opacityValue').textContent='30%';act('opacity',{themeId:selected.id,value:null});}};
function setLaunchBusy(value){$('launch').disabled=value;$('desktopConnect').disabled=value;$('applySelected').disabled=value;$('startPrompt').disabled=value;if(typeof AriaConnection!=='undefined')AriaConnection.render(state.desktopConnection);icons();}
async function start(themeId,prompt='',options={}){
 if(launchBusy)return;launchBusy=true;setLaunchBusy(true);
 const result=await act('launch',{themeId:themeId||state.activeId,prompt,...options});
 if(!result){launchBusy=false;setLaunchBusy(false);}else{toast('正在准备桌面端…');if($('preview').open)closePreview();}
}
async function openDesktop(){
 if(launchBusy)return;launchBusy=true;setLaunchBusy(true);
 const result=await act('launchDesktop');
 if(!result||result.waitingForExit){launchBusy=false;setLaunchBusy(false);}
}
$('launch').onclick=openDesktop;
$('desktopConnect').onclick=openDesktop;
$('applySelected').onclick=()=>start(selected?.id);
$('recordSelected').onclick=async()=>{if(selected){const result=await act('record',{themeId:selected.id,seconds:Number($('recordSeconds').value)});if(result){closePreview();go('jobs');}}};
$('addMedia').onclick=()=>act('addMedia');
$('addScene').onclick=()=>act('addScene',{seconds:Number($('recordSeconds').value)});
let lastHeroes='';
function setupHeroes(){
 lastHeroes=JSON.stringify(state.heroes);$('heroNext').disabled=state.heroes.length<2;if(!state.heroes.length)return;
 $('heroSlides').innerHTML=state.heroes.map((p,i)=>'<img class="hero-slide '+(i===hero?'show':'')+'" src="'+esc(p.url||('media/'+p.file))+'" alt="'+esc(p.title)+'">').join('');
 $('heroDots').innerHTML=state.heroes.map((p,i)=>'<button data-hero="'+i+'" aria-label="壁纸 '+(i+1)+'" class="'+(i===hero?'active':'')+'"></button>').join('');
 $('heroDots').querySelectorAll('button').forEach(b=>b.onclick=()=>{showHero(Number(b.dataset.hero));resetHeroAutoplay();});showHero(hero);
}
function showHero(index){if(!state.heroes.length)return;hero=index%state.heroes.length;document.querySelectorAll('.hero-slide').forEach((el,i)=>el.classList.toggle('show',i===hero));document.querySelectorAll('[data-hero]').forEach((el,i)=>el.classList.toggle('active',i===hero));$('heroTitle').textContent=state.heroes[hero].title;}
let heroAutoTimer;
function resetHeroAutoplay(){clearInterval(heroAutoTimer);heroAutoTimer=setInterval(()=>{if(!heroPaused&&page==='home'&&!document.hidden)showHero(hero+1);},6500);}
resetHeroAutoplay();
$('heroNext').onclick=()=>{showHero(hero+1);resetHeroAutoplay();};
$('heroPause').onclick=()=>{heroPaused=!heroPaused;$('heroPause').textContent=heroPaused?'▶':'Ⅱ';$('heroPause').ariaLabel=heroPaused?'继续轮播':'暂停轮播';};
$('heroUse').onclick=()=>act('importHero',{index:hero,heroId:state.heroes[hero]?.id||''});
const status={queued:'等待中',starting:'准备中',recording:'正在录制',finalizing:'正在入库',completed:'已完成',failed:'未完成',cancelled:'已取消','waiting-download':'等待 Steam 下载'};
let jobsSignature='';
async function clearCancelled(jobIds,all=false){
 const result=await act('clearCancelledJobs',{jobIds,all});if(!result)return;
 state.jobs=state.jobs.filter(j=>!(j.status==='cancelled'&&(all||jobIds.includes(j.id))));jobsSignature='';renderJobs();
}
function renderJobs(){
 const jobs=state.jobs.filter(j=>j.status!=='completed');
 const signature=JSON.stringify(jobs);if(signature===jobsSignature)return;jobsSignature=signature;
 $('emptyJobs').hidden=jobs.length>0;$('clearCancelled').hidden=!jobs.some(j=>j.status==='cancelled');
 $('jobList').innerHTML=[...jobs].reverse().map(j=>'<article class="job '+esc(j.status)+'"><div><h3>'+esc(j.name)+'<span>'+esc(status[j.status]||j.status)+(j.status==='waiting-download'?'':' · '+esc(j.percent)+'%')+'</span></h3><p>'+esc(j.message)+'</p><div class="job-stages">'+['等待下载 / 排队','本地校验 / 转换','加入皮肤库'].map((label,index)=>'<span class="'+(index===(j.status==='waiting-download'||j.status==='queued'?0:j.status==='finalizing'?2:1)?'current':'')+'">'+label+'</span>').join('')+'</div><div class="progress '+(j.status==='waiting-download'?'waiting':'')+'"><div data-percent="'+Math.max(0,Math.min(100,Number(j.percent)||0))+'"></div></div></div><div class="row">'+(['queued','starting','recording','waiting-download'].includes(j.status)?'<button class="soft" data-cancel="'+esc(j.id)+'">取消</button>':'')+(['failed','cancelled','waiting-download'].includes(j.status)?'<button class="soft" data-retry="'+esc(j.id)+'">'+(j.status==='waiting-download'?'检查下载':'重试')+'</button>':'')+(j.workshopId?'<button class="text" data-job-workshop="'+esc(j.workshopId)+'">查看项目</button>':'')+(j.status==='cancelled'?'<button class="soft" data-clear="'+esc(j.id)+'">清除</button>':'')+'</div></article>').join('');
 $('jobList').querySelectorAll('[data-percent]').forEach(el=>el.style.width=el.dataset.percent+'%');
 $('jobList').querySelectorAll('[data-cancel]').forEach(b=>b.onclick=()=>act('cancelJob',{jobId:b.dataset.cancel}));
 $('jobList').querySelectorAll('[data-retry]').forEach(b=>b.onclick=()=>act('retryJob',{jobId:b.dataset.retry}));
 $('jobList').querySelectorAll('[data-job-workshop]').forEach(b=>b.onclick=()=>{go('workshop');act('steamGo',{url:'https://steamcommunity.com/sharedfiles/filedetails/?id='+encodeURIComponent(b.dataset.jobWorkshop)});});
 $('jobList').querySelectorAll('[data-clear]').forEach(b=>b.onclick=()=>clearCancelled([b.dataset.clear]));
}
$('clearCancelled').onclick=()=>clearCancelled([],true);

function syncBounds(){if(page!=='workshop'&&page!=='wuwa')return;const r=$(page==='wuwa'?'wuwaViewport':'steamViewport').getBoundingClientRect();send(page==='wuwa'?'wuwaBounds':'steamBounds',{x:r.x,y:r.y,width:r.width,height:r.height,viewportWidth:window.innerWidth,viewportHeight:window.innerHeight}).catch(()=>{});}
new ResizeObserver(syncBounds).observe($('steamViewport'));new ResizeObserver(syncBounds).observe($('wuwaViewport'));window.addEventListener('scroll',syncBounds,{passive:true});window.addEventListener('resize',syncBounds);
$('steamBack').onclick=()=>act('steamBack');$('steamHome').onclick=()=>act('steamHome');$('steamReload').onclick=$('retrySteam').onclick=()=>act('steamReload');
$('steamGo').onclick=()=>act('steamGo',{url:$('steamUrl').value});$('steamUrl').onkeydown=e=>{if(e.key==='Enter')$('steamGo').click();};
$('steamRetry').onclick=()=>act('steamReload');$('steamExternal').onclick=()=>act('steamExternal');$('browseDownloaded').onclick=()=>act('browseDownloaded');
$('steamImport').onclick=()=>act('importWorkshop');
$('steamJobs').onclick=()=>go('jobs');
let promptsSignature='';
function renderPrompts(){
 if(typeof AriaPrompts!=='undefined'){AriaPrompts.render();return;}
 const signature=JSON.stringify(state.prompts);if(signature===promptsSignature)return;promptsSignature=signature;
 $('promptList').innerHTML=state.prompts.map(p=>'<button class="prompt-item '+(p.id===promptId?'active':'')+'" data-prompt="'+esc(p.id)+'"><b>'+esc(p.name)+'</b><small>'+esc(p.category||'我的收藏')+'</small></button>').join('');
 $('promptList').querySelectorAll('[data-prompt]').forEach(b=>b.onclick=()=>editPrompt(b.dataset.prompt));
}
function editPrompt(id){if(typeof AriaPrompts!=='undefined'){AriaPrompts.edit(id);return;}const p=state.prompts.find(p=>p.id===id);if(!p)return;promptId=id;$('promptName').value=p.name;$('promptText').value=p.text;$('workTask').value='';$('deletePrompt').hidden=!!p.builtin;promptsSignature='';renderPrompts();}
$('newPrompt').onclick=()=>{promptId=null;$('promptName').value='';$('promptText').value='';$('workTask').value='';$('deletePrompt').hidden=true;promptsSignature='';renderPrompts();$('promptName').focus();};
function composedPrompt(){const background=$('promptText').value.trim(),task=$('workTask').value.trim();return '# 本次工作的背景与要求\n'+background+(task?'\n\n# 这次要完成的任务\n'+task:'\n\n请先确认你理解以上工作要求，并问我这次想完成什么。');}
$('savePrompt').onclick=async()=>{const r=await act('savePrompt',{promptId,name:$('promptName').value,text:$('promptText').value});if(r?.promptId){promptId=r.promptId;promptsSignature='';renderPrompts();}};
$('copyPrompt').onclick=()=>act('copy',{text:composedPrompt()});
$('startPrompt').onclick=()=>{if(!$('promptText').value.trim()){toast('先写一点这次工作的背景吧 ♡');return;}start(state.activeId,composedPrompt());};
$('deletePrompt').onclick=async()=>{const r=await act('deletePrompt',{promptId});if(r){promptId=null;$('newPrompt').click();}};
$('savePolicy').onclick=()=>act('savePolicy',{videoMaxMB:Number($('videoLimit').value),sceneMaxMB:Number($('sceneLimit').value),autoImportWorkshop:$('autoWorkshop').checked});
$('openStorage').onclick=$('storageSettings').onclick=()=>act('openStorage');
$('sourceWuwa').onclick=()=>act('openSource',{site:'wuwa'});$('sourceEmoji').onclick=()=>act('openSource',{site:'emoji'});
act('ready');

document.querySelectorAll('[data-window-preset]').forEach(button=>button.onclick=()=>act('windowPreset',{preset:button.dataset.windowPreset}));
$('rememberWindow').onchange=()=>act('windowRemember',{value:$('rememberWindow').checked});



$('wuwaBack').onclick=()=>act('wuwaBack');$('wuwaHome').onclick=()=>act('wuwaHome');$('wuwaReload').onclick=$('wuwaRetry').onclick=()=>act('wuwaReload');$('wuwaExternal').onclick=()=>act('wuwaExternal');

$('heroSaved').onclick=()=>act('openSavedWallpapers');
