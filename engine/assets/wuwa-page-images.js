(()=>{
 const seen=new Set(),images=[];
 const publicUrl=value=>{try{const u=new URL(value,location.href);return u.protocol==='https:'&&!u.username&&!u.password?u.href:'';}catch{return ''}};
 function add(url,title,width,height,preview){url=publicUrl(url);if(!url||seen.has(url)||images.length>=40)return;seen.add(url);images.push({url,title:String(title||document.title||'鸣潮壁纸').slice(0,70),width:Number(width)||0,height:Number(height)||0,preview:publicUrl(preview)||url});}
 for(const img of [...document.images].slice(0,250)){
  const width=img.naturalWidth||Number(img.getAttribute('width'))||0,height=img.naturalHeight||Number(img.getAttribute('height'))||0;
  if(width<400&&height<300)continue;
  let source=img.getAttribute('data-original')||img.getAttribute('data-full')||img.currentSrc||img.src;
  const anchor=img.closest('a[href]');
  if(anchor&&/\.(?:jpe?g|png|webp|gif)(?:$|[?#])/i.test(anchor.href))source=anchor.href;
  add(source,img.alt||img.title,width,height,img.currentSrc||img.src);
 }
 for(const a of [...document.querySelectorAll('a[href]')].slice(0,250)){if(/\.(?:jpe?g|png|webp|gif)(?:$|[?#])/i.test(a.href)&&!a.querySelector('img'))add(a.href,a.title||a.textContent,0,0,a.href);}
 return {page:location.href,title:document.title,images};
})()