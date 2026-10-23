import fs from 'node:fs/promises';
const [stateFile, expectedTheme, timeoutArg='8000']=process.argv.slice(2);
const deadline=Date.now()+Number(timeoutArg);
const diagnosticHidden=process.argv.includes('--allow-hidden');
try {
 const state=JSON.parse(await fs.readFile(stateFile,'utf8'));
 const version=await (await fetch(`http://127.0.0.1:${state.port}/json/version`,{signal:AbortSignal.timeout(1500)})).json();
 if(!version.webSocketDebuggerUrl?.endsWith('/'+state.browserId))throw Error('session-changed');
 const targets=await (await fetch(`http://127.0.0.1:${state.port}/json/list`,{signal:AbortSignal.timeout(1500)})).json();
 const connections=[];
 for(const target of targets.filter(t=>t.type==='page'&&t.url.startsWith('app:'))){
  const u=new URL(target.webSocketDebuggerUrl);
  if(u.hostname!=='127.0.0.1'||Number(u.port)!==Number(state.port))continue;
  const ws=new WebSocket(u);await new Promise((r,j)=>{ws.onopen=r;ws.onerror=j;setTimeout(()=>j(Error('connect-timeout')),1500).unref()});connections.push(ws);
 }
 let sequence=0,pass=null;
 try {
  while(Date.now()<deadline){
   for(const ws of connections){
    const id=++sequence;
    const expression=`(() => {const s=window.__CODEX_DREAM_SKIN_STATE__,h=document.getElementById('dream-skin-window-background'),m=h?.querySelector('img,video');return {themeId:s?.themeId,visible:!document.hidden,ready:!!h&&!!m&&(m.tagName==='VIDEO'?s?.mediaDecoded:!!m.complete&&m.naturalWidth>0),error:s?.mediaError};})()`;
    const result=await new Promise((r,j)=>{const timer=setTimeout(()=>j(Error('status-timeout')),1500);ws.onmessage=e=>{const v=JSON.parse(e.data);if(v.id===id){clearTimeout(timer);r(v.result?.result?.value)}};ws.send(JSON.stringify({id,method:'Runtime.evaluate',params:{expression,returnByValue:true}}))});
    if(result?.error)throw Error(result.error);
    if((result?.visible||diagnosticHidden)&&result.ready&&(!expectedTheme||expectedTheme==='*'||result.themeId===expectedTheme)){pass=result;break;}
   }
   if(pass)break;
   await new Promise(r=>setTimeout(r,200));
  }
 } finally {connections.forEach(ws=>ws.close());}
 if(!pass)throw Error('window-not-ready');
 console.log(JSON.stringify({pass:true,...pass}));
}catch(error){console.error(error.message);process.exitCode=2;}
