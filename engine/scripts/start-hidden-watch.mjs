import fs from 'node:fs';import path from 'node:path';import{spawn}from'node:child_process';import{fileURLToPath}from'node:url';
export async function startHiddenNode(script,args,stdoutFile,stderrFile){
 const out=fs.openSync(stdoutFile,'a'),err=fs.openSync(stderrFile,'a');
 try{
  const child=spawn(process.execPath,[script,...args],{windowsHide:true,detached:true,stdio:['ignore',out,err]});
  await new Promise((resolve,reject)=>{child.once('spawn',resolve);child.once('error',reject)});
  child.unref();return child.pid;
 }finally{fs.closeSync(out);fs.closeSync(err)}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 const[stdoutFile,stderrFile,script,...args]=process.argv.slice(2);
 if(path.resolve(script)!==path.join(path.dirname(fileURLToPath(import.meta.url)),'injector.mjs'))throw Error('Unexpected watcher path');
 const pid=await startHiddenNode(script,args,stdoutFile,stderrFile);console.log(JSON.stringify({pid}));
}