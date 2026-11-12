const coverNorm=value=>String(value||'').normalize('NFKC').toLowerCase().replace(/ё/g,'е').replace(/[^\p{L}\p{N}]/gu,'');
function coverArtistMatch(a,b){const aliases={монеточка:'monetochka',моргенштерн:'morgenshtern',полматери:'polmateri',плм:'polmateri',оксимирон:'oxxxymiron'},first=value=>String(value).split(/\s+(?:feat\.?|ft\.?)\s+|[,;&]/i).map(coverNorm).map(v=>aliases[v]||v).filter(Boolean);const x=first(a),y=first(b);return coverNorm(a)===coverNorm(b)||x.some(v=>y.includes(v))}
function coverTitle(value){return coverNorm(String(value||'').replace(/\s*[([]\s*(?:feat\.?|ft\.?)\s+[^)\]]*[)\]]/gi,'').replace(/\s+(?:feat\.?|ft\.?)\s+.*$/i,''))}
function chooseCover(items,artist,title){return items.filter(t=>t.artworkUrl100&&coverArtistMatch(t.artistName,artist)&&(!title||coverTitle(t.trackName)===coverTitle(title))).sort((a,b)=>Number(b.trackExplicitness==='explicit')-Number(a.trackExplicitness==='explicit'))[0]}
const artworkJobs=new Map();
async function artworkLookup(env,artist,title){
 if(!title&&typeof ARTWORK_INDEX!=='undefined'){const portrait=ARTWORK_INDEX[coverNorm(artist)+'|'];if(portrait?.url)return{found:true,...portrait}}
 const key=(title?'artwork/v4/':'artwork/portraits-v1/')+hex(await crypto.subtle.digest('SHA-256',enc.encode(coverNorm(artist)+'|'+coverNorm(title))));
 const cached=await env.BUCKET.get(key);if(cached){const entry=JSON.parse(await cached.text());if(entry.until>Date.now()&&(entry.result?.found||entry.providers===2))return entry.result}
 const bundled=typeof ARTWORK_INDEX!=='undefined'?ARTWORK_INDEX[coverNorm(artist)+'|'+coverNorm(title)]:null;if(bundled?.url)return{found:true,...bundled,url:!/^https?:/.test(bundled.url)?'https://pulse-vibe-music.desyatnichenkoiosyf2.chatgpt.site/'+bundled.url:bundled.url};
 if(artworkJobs.has(key))return artworkJobs.get(key);
 const job=(async()=>{
  try{const matched=await searchYandexArtwork(artist,title);if(matched){await env.BUCKET.put(key,JSON.stringify({until:Date.now()+30*86400000,providers:2,result:matched}));return matched}}catch{}
  try{const matched=await searchImportArtwork(artist,title);if(matched){await env.BUCKET.put(key,JSON.stringify({until:Date.now()+30*86400000,providers:2,result:matched}));return matched}}catch{}
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
async function artworkRoute(r,env){const url=new URL(r.url);if(url.pathname!=='/api/artwork'||r.method!=='GET')return null;const artist=String(url.searchParams.get('artist')||'').trim(),title=String(url.searchParams.get('title')||'').trim();if(!artist||artist.length>100||title.length>150)return json(r,{error:'Нужны название и исполнитель'},400);try{const result=await artworkLookup(env,artist,title);if(result.found)await env.DB.prepare('UPDATE pulse_catalog SET cover_url=? WHERE title=? AND artist=?').bind(result.url,title,artist).run();return json(r,result)}catch(e){console.warn('Artwork provider failed:',e.message);return json(r,{error:'Не удалось загрузить обложку'},502)}}

function bundledArtworkUrl(artist,title){const cover=typeof ARTWORK_INDEX!=='undefined'?ARTWORK_INDEX[coverNorm(artist)+'|'+coverNorm(title)]:null;return cover?.url?(/^https?:/.test(cover.url)?cover.url:'https://pulse-vibe-music.desyatnichenkoiosyf2.chatgpt.site/'+cover.url):''}
async function searchYandexArtwork(artist,title){if(!title){const response=await fetch('https://api.music.yandex.net/search?'+new URLSearchParams({text:artist,type:'artist',page:'0'}),{signal:AbortSignal.timeout(8000)});if(!response.ok)return null;const data=await response.json(),hits=(data.result?.artists?.results||[]).filter(a=>coverArtistMatch(a.name,artist)&&coverNorm(a.name)===coverNorm(artist)).sort((a,b)=>Number(b.cover?.type==='from-artist-photos')-Number(a.cover?.type==='from-artist-photos')),hit=hits[0],image=hit?.cover?.uri;if(!image?.startsWith('avatars.yandex.net/get-music-content/'))return null;return{found:true,url:'https://'+image.replace('%%','600x600'),source:'Яндекс Музыка',sourceUrl:'https://music.yandex.ru/artist/'+hit.id}}const clean=s=>String(s).replace(/\s*\([^)]*(?:раунд|17\s*ib)[^)]*\)/ig,'').replace(/\s*\(prod\.[^)]*\)/ig,'').trim();const response=await fetch('https://api.music.yandex.net/search?'+new URLSearchParams({text:artist+' '+clean(title),type:'track',page:'0'}),{signal:AbortSignal.timeout(8000)});if(!response.ok)return null;const data=await response.json(),items=data.result?.tracks?.results||[];const hit=items.find(t=>coverArtistMatch(t.artists?.map(a=>a.name).join(' & '),artist)&&[clean(t.title),clean(t.title+(t.version?' ('+t.version+')':''))].some(v=>coverTitle(v)===coverTitle(clean(title)))&&(!/remix|instrumental|hip.hop version|live/i.test(title)||coverTitle(t.title+' '+(t.version||''))===coverTitle(title)));const image=hit?.coverUri||hit?.albums?.[0]?.coverUri;if(!image||!image.startsWith('avatars.yandex.net/get-music-content/'))return null;return{found:true,url:'https://'+image.replace('%%','600x600'),source:'Яндекс Музыка',sourceUrl:'https://music.yandex.ru/track/'+hit.id}}

function sourceCoverDecode(value){return String(value||'').replace(/&(?:amp|quot|apos|#39|lt|gt);/g,x=>({'&amp;':'&','&quot;':'"','&apos;':"'",'&#39;':"'",'&lt;':'<','&gt;':'>'}[x]))}
async function searchImportArtwork(artist,title){
 if(!title)return null;
 const source='https://one.muzso.net/query?'+new URLSearchParams({q:artist+' '+title.replace(/\s*[([](?:feat\.?|ft\.?)[^)]*[)\]]/ig,'')});
 const response=await fetch(source,{headers:{'user-agent':'Mozilla/5.0 PulseImport/1.0'},signal:AbortSignal.timeout(10000)});if(!response.ok)return null;
 const html=await response.text();if(html.length>2000000)return null;
 for(const tag of html.matchAll(/<div\b[^>]*\bdata-tid="[^"]+"[^>]*>/g)){
  const attrs={};for(const a of tag[0].matchAll(/\b(data-[\w-]+)="([^"]*)"/g))attrs[a[1]]=sourceCoverDecode(a[2]);
  if(!coverArtistMatch(attrs['data-artist'],artist)||coverTitle(attrs['data-title'])!==coverTitle(title))continue;
  let url;try{url=new URL(attrs['data-thumb'])}catch{continue}
  if(url.protocol!=='https:'||!['yt3.googleusercontent.com','i.ytimg.com','img.youtube.com'].includes(url.hostname))continue;
  return {found:true,url:url.href,source:'Источник импорта',sourceUrl:source};
 }
 return null;
}
