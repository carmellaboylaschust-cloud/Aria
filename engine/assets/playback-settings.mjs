import fs from 'node:fs/promises';
export const PLAYBACK_MODES=new Set(['normal','battery','static']);
export const PLAYBACK_SETTINGS_PATH='D:/Aria/user-backgrounds/playback-settings.json';
export async function readVideoAudioEnabled({preferencesPath=PLAYBACK_SETTINGS_PATH}={}){
 try{const value=JSON.parse((await fs.readFile(preferencesPath,'utf8')).replace(/^\uFEFF/,''));return value.schemaVersion===1&&value.audioEnabled===true;}catch{return false;}
}
export async function readPlaybackPolicy({preferencesPath=PLAYBACK_SETTINGS_PATH}={}){
 try{const value=JSON.parse(await fs.readFile(preferencesPath,'utf8'));return value.schemaVersion===1&&PLAYBACK_MODES.has(value.mode)?value.mode:'normal';}catch{return 'normal';}
}
