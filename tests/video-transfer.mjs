import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
const {loadPayload,ensureLocalVideo}=await import(pathToFileURL(path.join(process.argv[2],'scripts/injector.mjs')));
const temp=await fs.mkdtemp(path.join(os.tmpdir(),'aria-transfer-'));
const file=path.join(temp,'fixture.mp4');
const bytes=Buffer.alloc(2*1024*1024+17);for(let i=0;i<bytes.length;i++)bytes[i]=i%251;
const key=createHash('sha256').update(bytes).digest('hex');
function session(native, supersede=false){
 let blob=null,nativeCalls=0;
 class ByteArray extends Uint8Array {}
 if(native)ByteArray.fromBase64=data=>{nativeCalls++;return new ByteArray(Buffer.from(data,'base64'));};
 const state={mediaKey:key,mediaReady:false,setMediaUrl(){this.mediaReady=true;}};
 const context=vm.createContext({window:{__CODEX_DREAM_SKIN_STATE__:state},Uint8Array:ByteArray,Blob,URL:{createObjectURL(value){blob=value;return 'blob:synthetic';}},atob:data=>Buffer.from(data,'base64').toString('binary')});
 return {evaluate:async code=>{if(supersede&&code.includes('u.chunks.push'))state.mediaKey='changed';return vm.runInContext(code,context);},state,context,get blob(){return blob;},get nativeCalls(){return nativeCalls;}};
}
try{
 await fs.writeFile(file,bytes);
 const loaded=await loadPayload(undefined,{theme:{id:'test-video-transfer',mediaKind:'video',artMetadata:{mime:'video/mp4'}},imagePath:file,mediaHash:key});
 for(const native of [true,false]){
  const s=session(native);await ensureLocalVideo(s,loaded.payload);
  assert.equal(s.state.mediaReady,true);
  assert.deepEqual(Buffer.from(await s.blob.arrayBuffer()),bytes);
  assert.equal(s.context.window.__DREAM_VIDEO_UPLOAD__,undefined);
  assert.equal(s.nativeCalls,native?3:0);
 }
 const cancelled=session(true,true);await assert.rejects(ensureLocalVideo(cancelled,loaded.payload),/superseded/);
 assert.equal(cancelled.blob,null);assert.equal(cancelled.context.window.__DREAM_VIDEO_UPLOAD__,undefined);
 await fs.writeFile(file,Buffer.from('changed since validation'));
 const changed=session(true);await assert.rejects(ensureLocalVideo(changed,loaded.payload),/changed during transfer/);
 assert.equal(changed.blob,null);assert.equal(changed.context.window.__DREAM_VIDEO_UPLOAD__,undefined);
 console.log('Video transfer checks passed: native decode, fallback decode, exact bytes, superseded theme, changed source, cleanup.');
}finally{await fs.unlink(file).catch(()=>{});await fs.rmdir(temp);}
