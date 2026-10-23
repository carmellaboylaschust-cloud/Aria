import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {readImageMetadata} from './image-metadata.mjs';
const HOME='D:/Aria/user-backgrounds';
const HOSTS=new Set(['wuwa.games','www.wuwa.games','media.wuwa.win','media.wuwa.games','huiji-public.huijistatic.com','huiji-thumb.huijistatic.com','prod-alicdn-community.kurobbs.com']);
const IMAGE_EXT=new Set(['.jpg','.jpeg','.png','.webp','.gif']);
export function dailySlot(now=new Date()){
 const d=new Date(now);if(d.getHours()<4)d.setDate(d.getDate()-1);
 return [d.getFullYear(),String(d.getMonth()+1).padStart(2,'0'),String(d.getDate()).padStart(2,'0')].join('-');
}
export function nextDailyChange(now=new Date()){const d=new Date(now);d.setHours(4,0,0,0);if(d<=now)d.setDate(d.getDate()+1);return d;}
function allowed(value){const u=new URL(value);if(u.protocol!=='https:'||u.username||u.password||!HOSTS.has(u.hostname))throw Error('Unsupported wallpaper source');return u;}
async function safeDirectory(directory){
 const full=path.resolve(directory);if(!full.toLowerCase().startsWith(path.resolve('D:/Aria').toLowerCase()+path.sep))throw Error('Storage escaped D drive app folder');
 let current=path.parse(full).root;for(const part of full.slice(current.length).split(path.sep)){current=path.join(current,part);try{if((await fs.lstat(current)).isSymbolicLink())throw Error('Linked storage is not allowed')}catch(e){if(e.code!=='ENOENT')throw e}}
 await fs.mkdir(full,{recursive:true});return full;
}
async function json(file,fallback=null){try{return JSON.parse((await fs.readFile(file,'utf8')).replace(/^\uFEFF/,''))}catch{return fallback}}
async function atomic(file,value){
 const temp=file+'.'+crypto.randomUUID()+'.tmp';await fs.writeFile(temp,JSON.stringify(value,null,2),{flag:'wx'});
 try{for(let i=0;;i++){try{await fs.rename(temp,file);break}catch(e){if(i>=6)throw e;await new Promise(r=>setTimeout(r,60))}}}finally{await fs.unlink(temp).catch(()=>{})}
}
async function request(value,maxBytes,fetcher=fetch){
 let u=allowed(value);for(let redirect=0;redirect<4;redirect++){
  const response=await fetcher(u.href,{redirect:'manual',signal:AbortSignal.timeout(20000),headers:{'user-agent':'AriaWallpaper/1.0 (+https://wuwa.games/)'}});
  if(response.status>=300&&response.status<400){u=allowed(new URL(response.headers.get('location'),u).href);continue}
  if(!response.ok)throw Error('HTTP '+response.status);
  if(Number(response.headers.get('content-length')||0)>maxBytes){await response.body?.cancel();throw Error('Wallpaper is too large')}
  const chunks=[];let bytes=0;
  try{for await(const chunk of response.body){bytes+=chunk.length;if(bytes>maxBytes)throw Error('Wallpaper exceeds size limit');chunks.push(chunk)}}catch(e){await response.body?.cancel().catch(()=>{});throw e}
  return {bytes:Buffer.concat(chunks),mime:(response.headers.get('content-type')||'').split(';')[0],url:u.href};
 }throw Error('Too many redirects');
}
export async function loadCatalog(fetcher=fetch){
 const html=(await request('https://wuwa.games/',2*1024*1024,fetcher)).bytes.toString('utf8');
 const scripts=[...html.matchAll(/<script\b[^>]*\bsrc=["']([^"']+)["']/gi)].map(m=>new URL(m[1],'https://wuwa.games/').href);
 const source=scripts.find(value=>/\/config\.js(?:\?|$)/.test(value));
 if(!source)throw Error('The wallpaper catalog is temporarily unavailable');
 const text=(await request(source,2*1024*1024,fetcher)).bytes.toString('utf8');
 const match=text.match(/window\.WUWA_CONFIG\s*=\s*(\{[\s\S]*\})\s*;?\s*$/);
 if(!match)throw Error('The catalog format changed; previous recommendations were retained');
 const config=JSON.parse(match[1]);
 if(!Array.isArray(config.posters))throw Error('The catalog has no wallpapers');
 return config.posters.filter(p=>p.type==='image'&&p.orientation==='landscape'&&typeof p.src==='string').map(p=>({title:String(p.title||'鸣潮壁纸').slice(0,100),original:allowed(p.src).href,mirror:p.mirror&&allowed(p.mirror).href,source:'https://wuwa.games/'}));
}
export async function cleanupOldCache(cache,keep){
 const removed=[];for(const entry of await fs.readdir(cache,{withFileTypes:true})){
  if(!entry.isFile()||!/^[a-f0-9]{64}\.(jpg|jpeg|png|webp|gif)$/.test(entry.name)||keep.has(entry.name))continue;
  // Direct unlink: expired recommendations are removed from disk, not moved to a recycle bin.
  try{await fs.unlink(path.join(cache,entry.name));removed.push(entry.name)}catch(e){if(!['EPERM','EBUSY','EACCES'].includes(e.code))throw e}
 }return removed;
}
export async function cleanupLegacyRecommendations(home,manifest){
 const inventoryPath=path.join(home,'daily-wallpapers','legacy-recommendations.json');
 const inventory=await json(inventoryPath,[]);if(!Array.isArray(inventory)||!inventory.length)return 0;
 const retained=new Set((manifest?.heroes||[]).map(h=>h.hash));let removed=0;const pending=[];
 const appRoot=path.resolve('D:/Aria')+path.sep;
 for(const item of inventory){
  const target=path.resolve(String(item.path||''));
  // Only installer-owned historical recommendation copies are eligible; user libraries and Steam are excluded.
  if(!target.toLowerCase().startsWith(appRoot.toLowerCase())||!/[\\\\/]hub[\\\\/]media[\\\\/]hero-[0-3]\.jpg$/i.test(target)||!/^[a-f0-9]{64}$/.test(item.hash))continue;
  if(retained.has(item.hash)){pending.push(item);continue}
  try{
   await safeDirectory(path.dirname(target));const entry=await fs.lstat(target);if(!entry.isFile()||entry.isSymbolicLink())continue;
   if(crypto.createHash('sha256').update(await fs.readFile(target)).digest('hex')!==item.hash)continue;
   await fs.unlink(target);removed++;
  }catch(e){if(e.code!=='ENOENT')pending.push(item)}
 }
 await atomic(inventoryPath,pending);return removed;
}
export async function refreshDailyFeed({home=HOME,now=new Date(),candidates=null,fetcher=fetch,force=false}={}){
 home=await safeDirectory(home);
 const root=await safeDirectory(path.join(home,'daily-wallpapers')),cache=await safeDirectory(path.join(root,'cache'));
 await safeDirectory(path.join(home,'saved-wallpapers'));
 const manifestPath=path.join(root,'current.json'),previous=await json(manifestPath);
 const slot=dailySlot(now);
 if(!force&&previous?.slot===slot&&previous.heroes?.length===4&&await Promise.all(previous.heroes.map(h=>fs.access(path.join(home,h.relativePath)).then(()=>true,()=>false))).then(v=>v.every(Boolean)))return {changed:false,slot};
 const stat=await fs.statfs(home);if(Number(stat.bavail)*Number(stat.bsize)<2*1024**3)throw Error('D drive has less than 2 GB available');
 const catalog=candidates||await loadCatalog(fetcher);
 const seed=previous?.heroes||(await json(path.join(home,'daily-wallpapers','initial-sources.json'),[]));
 const previousSources=new Set(seed.map(h=>h.original));
 const previousHashes=new Set((previous?.heroes||[]).map(h=>h.hash));
 const ranked=catalog.filter(p=>!previousSources.has(p.original)).sort((a,b)=>crypto.createHash('sha256').update(slot+a.original).digest('hex').localeCompare(crypto.createHash('sha256').update(slot+b.original).digest('hex')));
 if(ranked.length<4)throw Error('Fewer than four new wallpapers are available; old recommendations were retained');
 const prefs=await json(path.join(home,'import-policy.json'),{}),maxBytes=Math.max(1,Math.min(32,Number(prefs.imageMaxMB)||32))*1024**2;
 const selected=[],newFiles=[];let committed=false;const seen=new Set();
 try{
  for(const item of ranked.slice(0,24)){
   try{
    let image;for(const url of [...new Set([item.original,item.mirror].filter(Boolean))]){try{image=await request(url,maxBytes,fetcher);break}catch{}}
    if(!image)continue;
    let ext=path.extname(new URL(image.url).pathname).toLowerCase();
    if(!IMAGE_EXT.has(ext))ext=({'image/jpeg':'.jpg','image/png':'.png','image/webp':'.webp','image/gif':'.gif'})[image.mime];
    if(!IMAGE_EXT.has(ext))continue;
    const metadata=readImageMetadata(image.bytes,ext);
    if(!metadata||metadata.width<metadata.height)continue;
    const hash=crypto.createHash('sha256').update(image.bytes).digest('hex');
    if(previousHashes.has(hash)||seen.has(hash))continue;seen.add(hash);
    const filename=hash+ext,target=path.join(cache,filename);
    try{await fs.access(target)}catch{const temp=target+'.'+crypto.randomUUID()+'.tmp';try{await fs.writeFile(temp,image.bytes,{flag:'wx'});await fs.rename(temp,target);newFiles.push(target)}finally{await fs.unlink(temp).catch(()=>{})}}
    selected.push({id:hash.slice(0,24),hash,title:item.title,original:item.original,source:'https://wuwa.games/',relativePath:path.posix.join('daily-wallpapers','cache',filename),width:metadata.width,height:metadata.height});
    if(selected.length===4)break;
   }catch{}
  }
  if(selected.length!==4)throw Error('Could not fetch four valid new wallpapers; old recommendations were retained');
  const manifest={schemaVersion:1,slot,refreshedAt:new Date(now).toISOString(),nextChange:nextDailyChange(now).toISOString(),heroes:selected};
  await atomic(manifestPath,manifest);committed=true;
  const removed=await cleanupOldCache(cache,new Set(selected.map(h=>path.basename(h.relativePath))));
  const legacyRemoved=await cleanupLegacyRecommendations(home,manifest);
  return {changed:true,slot,removed:removed.length,legacyRemoved,heroes:selected};
 }catch(e){if(committed)throw e;for(const file of newFiles)await fs.unlink(file).catch(()=>{});throw e}
}
export async function runDailyWorker(){
 const root=await safeDirectory(path.join(HOME,'daily-wallpapers'));
 const statusPath=path.join(root,'status.json');let retryAt=0;
 for(;;){
  const now=new Date(),current=await json(path.join(root,'current.json'));
  if(current?.slot!==dailySlot(now)&&Date.now()>=retryAt){
   try{await atomic(statusPath,{state:'refreshing',at:now.toISOString()});const result=await refreshDailyFeed({now});await atomic(statusPath,{state:'ready',slot:result.slot,at:new Date().toISOString(),nextChange:nextDailyChange().toISOString()});retryAt=0}
   catch(e){retryAt=Date.now()+10*60*1000;await atomic(statusPath,{state:'retry',message:e.message,at:new Date().toISOString(),retryAt:new Date(retryAt).toISOString()})}
  }
  const active=await json(path.join(root,'current.json'));if(active?.heroes?.length===4)await cleanupOldCache(path.join(root,'cache'),new Set(active.heroes.map(h=>path.basename(h.relativePath)))).catch(()=>{});
  if(active?.heroes?.length===4)await cleanupLegacyRecommendations(HOME,active).catch(()=>{});
  const seconds=Math.max(1,Math.min(60,Math.ceil((nextDailyChange()-new Date())/1000)));
  await new Promise(resolve=>setTimeout(resolve,seconds*1000));
 }
}
const own=fileURLToPath(import.meta.url);
if(process.argv[1]&&path.resolve(process.argv[1])===own){
 if(process.argv.includes('--worker'))await runDailyWorker();
 else if(process.argv.includes('--once'))console.log(JSON.stringify(await refreshDailyFeed()));
}
