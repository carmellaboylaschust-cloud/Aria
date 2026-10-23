import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const SOF_MARKERS = new Set([
  0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7,
  0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf,
]);
export const MAX_IMAGE_DIMENSION = 16384;
export const MAX_IMAGE_PIXELS = 50_000_000;

function uint16be(bytes, offset) {
  return bytes[offset] * 256 + bytes[offset + 1];
}

function uint16le(bytes, offset) {
  return bytes[offset] + bytes[offset + 1] * 256;
}

function uint24le(bytes, offset) {
  return bytes[offset] + bytes[offset + 1] * 256 + bytes[offset + 2] * 65536;
}

function uint32be(bytes, offset) {
  return bytes[offset] * 0x1000000 + bytes[offset + 1] * 0x10000 +
    bytes[offset + 2] * 0x100 + bytes[offset + 3];
}

function uint32le(bytes, offset) {
  return bytes[offset] + bytes[offset + 1] * 0x100 + bytes[offset + 2] * 0x10000 +
    bytes[offset + 3] * 0x1000000;
}

function ascii(bytes, offset, length) {
  return String.fromCharCode(...bytes.subarray(offset, offset + length));
}

function pngDimensions(bytes) {
  const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (bytes.length < 24 || signature.some((value, index) => bytes[index] !== value) ||
      uint32be(bytes, 8) !== 13 || ascii(bytes, 12, 4) !== "IHDR") return null;
  const width = uint32be(bytes, 16);
  const height = uint32be(bytes, 20);
  return width > 0 && height > 0 ? { width, height } : null;
}

function gifDimensions(bytes) {
  if (bytes.length < 13 || !["GIF87a", "GIF89a"].includes(ascii(bytes, 0, 6))) return null;
  return { width: uint16le(bytes, 6), height: uint16le(bytes, 8) };
}

function jpegDimensions(bytes) {
  if (bytes.length < 12 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return null;
  let offset = 2;
  while (offset + 9 < bytes.length) {
    if (bytes[offset] !== 0xff) {
      offset += 1;
      continue;
    }
    while (offset < bytes.length && bytes[offset] === 0xff) offset += 1;
    const marker = bytes[offset++];
    if (marker === 0xd9 || marker === 0xda) break;
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd8)) continue;
    if (offset + 2 > bytes.length) break;
    const length = uint16be(bytes, offset);
    if (length < 2 || offset + length > bytes.length) break;
    if (SOF_MARKERS.has(marker) && length >= 7) {
      const height = uint16be(bytes, offset + 3);
      const width = uint16be(bytes, offset + 5);
      return width > 0 && height > 0 ? { width, height } : null;
    }
    offset += length;
  }
  return null;
}

function webpDimensions(bytes) {
  if (bytes.length < 20 || ascii(bytes, 0, 4) !== "RIFF" || ascii(bytes, 8, 4) !== "WEBP") {
    return null;
  }
  const riffEnd = Math.min(bytes.length, uint32le(bytes, 4) + 8);
  let offset = 12;
  while (offset + 8 <= riffEnd) {
    const type = ascii(bytes, offset, 4);
    const size = bytes[offset + 4] + bytes[offset + 5] * 256 +
      bytes[offset + 6] * 65536 + bytes[offset + 7] * 0x1000000;
    const data = offset + 8;
    if (data + size > riffEnd) break;
    if (type === "VP8X" && size >= 10) {
      return { width: uint24le(bytes, data + 4) + 1, height: uint24le(bytes, data + 7) + 1 };
    }
    if (type === "VP8L" && size >= 5 && bytes[data] === 0x2f) {
      const width = 1 + bytes[data + 1] + ((bytes[data + 2] & 0x3f) << 8);
      const height = 1 + (bytes[data + 2] >> 6) + (bytes[data + 3] << 2) +
        ((bytes[data + 4] & 0x0f) << 10);
      return { width, height };
    }
    if (type === "VP8 " && size >= 10 && bytes[data + 3] === 0x9d &&
      bytes[data + 4] === 0x01 && bytes[data + 5] === 0x2a) {
      return {
        width: uint16le(bytes, data + 6) & 0x3fff,
        height: uint16le(bytes, data + 8) & 0x3fff,
      };
    }
    offset = data + size + (size % 2);
  }
  return null;
}

export function classifyImageDimensions({ width, height }) {
  const ratio = width / height;
  if (
    !Number.isSafeInteger(width) || !Number.isSafeInteger(height)
    || width < 1 || height < 1
    || width > MAX_IMAGE_DIMENSION || height > MAX_IMAGE_DIMENSION
    || width * height > MAX_IMAGE_PIXELS
    || !Number.isFinite(ratio)
  ) return null;
  const aspect = ratio >= 2.25 ? "ultrawide" : ratio >= 1.45 ? "wide"
    : ratio >= 1.08 ? "landscape" : ratio >= 0.9 ? "square" : "portrait";
  return {
    width,
    height,
    ratio,
    wide: ratio >= 1.75,
    aspect,
    taskMode: ratio >= 2.25 ? "banner" : "ambient",
  };
}

// Raw pixel dimensions straight from the container header — no decode, and no
// safety-cap classification, so callers can reject oversized images *before*
// anything rasterizes them. Returns null for formats this header parser does
// not recognize (e.g. HEIC/TIFF).
export function readRawDimensions(value, extension = "") {
  const bytes = value instanceof Uint8Array ? value : new Uint8Array(value);
  const normalized = extension.toLowerCase();
  if (normalized === ".gif" || ascii(bytes, 0, 3) === "GIF") return gifDimensions(bytes);
  if (normalized === ".png" || bytes[0] === 0x89) return pngDimensions(bytes);
  if (normalized === ".jpg" || normalized === ".jpeg" ||
    (bytes[0] === 0xff && bytes[1] === 0xd8)) return jpegDimensions(bytes);
  if (normalized === ".webp" || ascii(bytes, 8, 4) === "WEBP") return webpDimensions(bytes);
  return null;
}

export function readImageAnimation(value, extension = "") {
 const b=value instanceof Uint8Array?value:new Uint8Array(value);let frames=1;
 if(ascii(b,0,4)==="RIFF"&&ascii(b,8,4)==="WEBP"){
  let o=12,n=0,end=Math.min(b.length,uint32le(b,4)+8);
  while(o+8<=end){const type=ascii(b,o,4),size=uint32le(b,o+4),data=o+8;if(data+size>end)break;if(type==="ANMF")n++;o=data+size+(size%2);}
  frames=Math.max(1,n);
 }else if(["GIF87a","GIF89a"].includes(ascii(b,0,6))&&b.length>=13){
  let o=13+((b[10]&128)?3*(1<<((b[10]&7)+1)):0),n=0;
  const skip=()=>{while(o<b.length){const size=b[o++];if(!size)return;o+=size;}};
  while(o<b.length){
   const marker=b[o++];if(marker===0x3b)break;
   if(marker===0x21){o++;skip();}
   else if(marker===0x2c){if(o+9>b.length)break;const packed=b[o+8];o+=9;if(packed&128)o+=3*(1<<((packed&7)+1));o++;skip();n++;}
   else break;
  }
  frames=Math.max(1,n);
 }else if(ascii(b,1,3)==="PNG"){
  let o=8;while(o+12<=b.length){const size=uint32be(b,o),type=ascii(b,o+4,4);if(o+size+12>b.length)break;if(type==="acTL"&&size>=8){frames=Math.max(1,uint32be(b,o+8));break;}o+=12+size;}
 }
 return {animated:frames>1,frames};
}
export function readImageMetadata(value, extension = "") {
  const dimensions = readRawDimensions(value, extension);
  return dimensions ? classifyImageDimensions(dimensions) : null;
}

// Keep the PowerShell theme store on the same strict parser as the injector.
// The CLI is intentionally tiny: it only reads a user-selected file and emits
// validated dimensions; it never writes or follows a caller-provided output.
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [mode, imagePath] = process.argv.slice(2);
  if (mode !== "--check" || !imagePath) {
    console.error("Usage: image-metadata.mjs --check <image>");
    process.exitCode = 2;
  } else {
    try {
      const resolved = path.resolve(imagePath);
      const bytes = await fs.readFile(resolved);
      const metadata = readImageMetadata(bytes, path.extname(resolved));
      if (!metadata) throw new Error("Image metadata is invalid or exceeds the 16384px / 50MP safety limit");
      console.log(JSON.stringify({...metadata,...readImageAnimation(bytes,path.extname(resolved))}));
    } catch (error) {
      console.error(error?.message ?? String(error));
      process.exitCode = 2;
    }
  }
}
