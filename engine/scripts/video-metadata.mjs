import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {classifyImageDimensions} from './image-metadata.mjs';

export const MAX_VIDEO_BYTES=256*1024*1024;
export async function readVideoMetadata(file) {
 const handle=await fs.open(file,'r');
 try {
  const stat=await handle.stat();
  if(!stat.isFile()||stat.size<16||stat.size>MAX_VIDEO_BYTES) throw Error('视频须在 256 MB 以内');
  const read=async(at,n)=>{const b=Buffer.alloc(n);const {bytesRead}=await handle.read(b,0,n,at);if(bytesRead!==n)throw Error('视频文件不完整');return b;};
  let dimensions=null;
  const ext=path.extname(file).toLowerCase();
  if(ext==='.mp4') {
   let at=0;
   while(at+8<=stat.size) {
    let h=await read(at,Math.min(16,stat.size-at));let size=h.readUInt32BE(0),head=8;
    if(size===1){if(h.length<16)throw Error('无效 MP4');size=Number(h.readBigUInt64BE(8));head=16;}
    if(size===0)size=stat.size-at;
    if(!Number.isSafeInteger(size)||size<head||at+size>stat.size)throw Error('无效 MP4 区块');
    if(h.toString('ascii',4,8)==='moov') {
     if(size>32*1024*1024)throw Error('MP4 元数据过大');
     const moov=await read(at+head,size-head);
     const walk=(start,end)=>{
      for(let p=start;p+8<=end;){
       let n=moov.readUInt32BE(p),len=8;
       if(n===1){if(p+16>end)break;n=Number(moov.readBigUInt64BE(p+8));len=16;}
       if(n===0)n=end-p;
       if(!Number.isSafeInteger(n)||n<len||p+n>end)break;
       const type=moov.toString('ascii',p+4,p+8);
       if(type==='trak')walk(p+len,p+n);
       if(type==='tkhd'&&n>=len+84){
        const w=moov.readUInt32BE(p+n-8)/65536,h=moov.readUInt32BE(p+n-4)/65536;
        if(w>0&&h>0)dimensions={width:Math.round(w),height:Math.round(h)};
       }
       p+=n;
      }
     };walk(0,moov.length);break;
    }
    at+=size;
   }
  } else if(ext==='.webm') {
   const bytes=await read(0,Math.min(stat.size,4*1024*1024));
   if(bytes.readUInt32BE(0)!==0x1a45dfa3)throw Error('无效 WebM');
   const vint=(p,id=false)=>{
    const first=bytes[p];if(!first)return null;
    let len=1,mask=128;while(!(first&mask)&&len<=8){len++;mask>>=1;}
    if(len>8||p+len>bytes.length)return null;
    let value=id?first:first&(mask-1);for(let j=1;j<len;j++)value=value*256+bytes[p+j];
    return {len,value};
   };
   const containers=new Set([0x1a45dfa3,0x18538067,0x1654ae6b,0xae,0xe0]);
   let width,height;
   const walk=(start,end,depth=0)=>{
    if(depth>8)return;
    for(let p=start;p<end;){
     const id=vint(p,true);if(!id)break;const size=vint(p+id.len);if(!size)break;
     const data=p+id.len+size.len,finish=Math.min(data+size.value,end);
     if((id.value===0xb0||id.value===0xba)&&size.value>0&&size.value<=4&&data+size.value<=end){
      let n=0;for(let i=data;i<data+size.value;i++)n=n*256+bytes[i];
      if(id.value===0xb0)width=n;else height=n;
     }
     if(containers.has(id.value))walk(data,finish,depth+1);
     if(!Number.isSafeInteger(data+size.value)||data+size.value<=p)break;p=data+size.value;
    }
   };walk(0,bytes.length);dimensions={width,height};
  } else throw Error('仅支持 MP4 和 WebM 视频');
  const metadata=dimensions&&classifyImageDimensions(dimensions);
  if(!metadata)throw Error('无法识别视频尺寸，或视频超过 16384px / 50MP');
  return {...metadata,kind:'video',mime:ext==='.mp4'?'video/mp4':'video/webm'};
 } finally {await handle.close();}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{console.log(JSON.stringify(await readVideoMetadata(process.argv[2])));}catch(e){console.error(e.message);process.exitCode=2;}
}
