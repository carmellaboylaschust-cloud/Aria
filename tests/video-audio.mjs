import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import {pathToFileURL} from 'node:url';
const root=process.argv[2];
const {readVideoAudioEnabled}=await import(pathToFileURL(path.join(root,'assets/playback-settings.mjs')));
const {syncVideoAudio}=await import(pathToFileURL(path.join(root,'scripts/injector.mjs')));
const directory=await fs.mkdtemp(path.join(os.tmpdir(),'aria-audio-'));
const preferencesPath=path.join(directory,'settings.json');
function player(hidden=false){
 const state={mediaKey:'synthetic',audioEnabled:false,calls:0,setAudioEnabled(value){this.calls++;this.audioEnabled=value;}};
 const document={hidden};
 const context=vm.createContext({window:{__CODEX_DREAM_SKIN_STATE__:state},document});
 return {state,document,evaluate:async expression=>vm.runInContext(expression,context)};
}
try{
 assert.equal(await readVideoAudioEnabled({preferencesPath}),false);
 for(const [value,expected] of [[{schemaVersion:1,mode:'normal'},false],[{schemaVersion:1,audioEnabled:true},true],[{schemaVersion:1,audioEnabled:'true'},false],[{schemaVersion:2,audioEnabled:true},false]]){
  await fs.writeFile(preferencesPath,'\uFEFF'+JSON.stringify(value));assert.equal(await readVideoAudioEnabled({preferencesPath}),expected);
 }
 const hidden=player(true),first=player(),second=player();
 await syncVideoAudio([hidden,first,second],true);
 assert.equal(hidden.state.audioEnabled,false);assert.equal(first.state.audioEnabled,true);assert.equal(second.state.audioEnabled,false);
 await syncVideoAudio([hidden,first,second],true);assert.equal(first.state.calls,1);
 first.document.hidden=true;await syncVideoAudio([hidden,first,second],true);
 assert.equal(first.state.audioEnabled,false);assert.equal(second.state.audioEnabled,true);
 await syncVideoAudio([hidden,first,second],false);assert.equal(second.state.audioEnabled,false);
 console.log('Video audio checks passed: default mute, persisted choice, strict values, single audible window, visibility handoff, instant mute.');
}finally{await fs.unlink(preferencesPath).catch(()=>{});await fs.rmdir(directory);}
