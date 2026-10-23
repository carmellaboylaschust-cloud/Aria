import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
const {readVideoMetadata}=await import(pathToFileURL(path.join(process.argv[2],'scripts/video-metadata.mjs')));
const open=fs.open;
// A valid MP4 metadata box with a synthetic file length avoids a 512 MB test download.
const bytes=Buffer.alloc(100);
bytes.writeUInt32BE(100,0);bytes.write('moov',4);
bytes.writeUInt32BE(92,8);bytes.write('tkhd',12);
bytes.writeUInt32BE(3840*65536,92);bytes.writeUInt32BE(2160*65536,96);
let size=512*1024*1024,closed=0;
fs.open=async()=>({stat:async()=>({isFile:()=>true,size}),read:async(b,o,n,p)=>{bytes.copy(b,o,p,p+n);return {bytesRead:n};},close:async()=>{closed++;}});
try{
 const result=await readVideoMetadata('synthetic.mp4');
 assert.equal(result.width,3840);assert.equal(result.height,2160);
 size++;await assert.rejects(readVideoMetadata('synthetic.mp4'),/512 MB/);
 assert.equal(closed,2);
 console.log('Video metadata checks passed: 512 MB accepted, 4K preserved, oversized rejected, handles closed.');
}finally{fs.open=open;}
