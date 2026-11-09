'use strict';
const AriaExperience=(()=>{
 const previous=document.createElement('button');previous.id='previousSkin';previous.className='soft';previous.textContent='恢复上一张';previous.hidden=true;
 document.querySelector('.library-organize').append(previous);
 previous.onclick=()=>start('', '',{restorePrevious:true});
 const queue=document.createElement('button');queue.id='queuePause';queue.className='soft';queue.textContent='暂停后续任务';$('clearCancelled').before(queue);
 let queueBusy=false;
 queue.onclick=async()=>{if(queueBusy)return;queueBusy=true;renderControls();try{const r=await act('queuePause',{paused:!state.queueSettings?.paused});if(r?.queueSettings)state.queueSettings=r.queueSettings;}finally{queueBusy=false;renderControls();}};
 const hint=document.createElement('p');hint.id='queuePausedNote';hint.className='queue-paused-note';hint.hidden=true;hint.textContent='后续任务已暂停，当前任务继续完成。';$('jobList').before(hint);
 function renderControls(){
  previous.hidden=!state.previousAvailable;previous.disabled=launchBusy;
  queue.disabled=queueBusy;queue.textContent=state.queueSettings?.paused?'继续队列':'暂停后续任务';queue.setAttribute('aria-pressed',String(!!state.queueSettings?.paused));hint.hidden=!state.queueSettings?.paused;
  for(const job of state.jobs){
   const cancel=[...$('jobList').querySelectorAll('[data-cancel]')].find(b=>b.dataset.cancel===job.id);if(!cancel||job.status!=='queued')continue;
   let priority=cancel.parentElement.querySelector('[data-priority]');
   if(!priority){priority=document.createElement('button');priority.className='text';priority.dataset.priority=job.id;cancel.before(priority);}
   const first=state.queueSettings?.priorityIds?.[0]===job.id;priority.textContent=first?'已优先':'优先处理';priority.disabled=first;
   priority.onclick=async()=>{priority.disabled=true;const r=await act('queuePriority',{jobId:job.id});if(r?.queueSettings)state.queueSettings=r.queueSettings;renderControls();};
  }
 }
 const originalAccept=acceptState;acceptState=data=>{originalAccept(data);renderControls();};
 const originalJobs=renderJobs;renderJobs=()=>{originalJobs();renderControls();};
 const originalBusy=setLaunchBusy;setLaunchBusy=value=>{originalBusy(value);renderControls();};
 window.chrome?.webview?.addEventListener('message',event=>{if(event.data.type==='privacyLocked'){state.previousAvailable=false;renderControls();}});
 renderControls();return {renderControls};
})();
