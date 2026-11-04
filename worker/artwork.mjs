const coverNorm=value=>String(value||'').normalize('NFKC').toLowerCase().replace(/ё/g,'е').replace(/[^\p{L}\p{N}]/gu,'');
function coverArtistMatch(a,b){const first=value=>String(value).split(/\s+(?:feat\.?|ft\.?)\s+|[,;&]/i).map(coverNorm).filter(Boolean);const x=first(a),y=first(b);return coverNorm(a)===coverNorm(b)||x.some(v=>y.includes(v))}
function chooseCover(items,artist,title){return items.filter(t=>t.artworkUrl100&&coverArtistMatch(t.artistName,artist)&&(!title||coverNorm(t.trackName)===coverNorm(title))).sort((a,b)=>Number(b.trackExplicitness==='explicit')-Number(a.trackExplicitness==='explicit'))[0]}
const artworkJobs=new Map();
async function artworkLookup(env,artist,title){
 const key='artwork/v3/'+hex(await crypto.subtle.digest('SHA-256',enc.encode(coverNorm(artist)+'|'+coverNorm(title))));
 const cached=await env.BUCKET.get(key);if(cached){const entry=JSON.parse(await cached.text());if(entry.until>Date.now())return entry.result}
 if(artworkJobs.has(key))return artworkJobs.get(key);
 const job=(async()=>{
  let hit;
  for(const country of ['us','kz']){
   const artistKey='artwork/artists-v3/'+country+'/'+hex(await crypto.subtle.digest('SHA-256',enc.encode(coverNorm(artist))));
   const saved=await env.BUCKET.get(artistKey);let entry=saved?JSON.parse(await saved.text()):null;
   if(!entry||entry.until<Date.now()){
    const params=new URLSearchParams({term:artist,entity:'song',limit:'200',country});
    const response=await fetch('https://itunes.apple.com/search?'+params,{signal:AbortSignal.timeout(10000)});if(!response.ok)throw Error('Каталог обложек временно недоступен');
    const data=await response.json();entry={until:Date.now()+86400000,items:(data.results||[]).map(t=>({artistName:t.artistName,trackName:t.trackName,artworkUrl100:t.artworkUrl100,trackViewUrl:t.trackViewUrl,trackExplicitness:t.trackExplicitness}))};await env.BUCKET.put(artistKey,JSON.stringify(entry));
   }
   hit=chooseCover(entry.items,artist,title);if(hit)break;
  }
  if(!hit&&title){
   const params=new URLSearchParams({term:artist+' '+title,entity:'song',limit:'25',country:'us'}),response=await fetch('https://itunes.apple.com/search?'+params,{signal:AbortSignal.timeout(10000)});
   if(!response.ok)throw Error('Каталог обложек временно недоступен');hit=chooseCover((await response.json()).results||[],artist,title);
  }
  let url=hit?.artworkUrl100||'';try{const parsed=new URL(url);if(parsed.protocol!=='https:'||!parsed.hostname.endsWith('.mzstatic.com'))url=''}catch{url=''}
  url=url.replace(/100x100[^/]*?(?=\.(?:jpg|png|webp))/i,'600x600bb');
  const result={found:!!url,url,source:'Apple Music',sourceUrl:hit?.trackViewUrl||''};await env.BUCKET.put(key,JSON.stringify({until:Date.now()+(url?30*86400000:6*3600000),result}));return result;
 })();artworkJobs.set(key,job);try{return await job}finally{artworkJobs.delete(key)}
}
async function artworkRoute(r,env){const url=new URL(r.url);if(url.pathname!=='/api/artwork'||r.method!=='GET')return null;const artist=String(url.searchParams.get('artist')||'').trim(),title=String(url.searchParams.get('title')||'').trim();if(!artist||artist.length>100||title.length>150)return json(r,{error:'Нужны название и исполнитель'},400);try{return json(r,await artworkLookup(env,artist,title))}catch{return json(r,{error:'Не удалось загрузить обложку'},502)}}
