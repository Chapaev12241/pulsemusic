// Public catalog metadata only. Full audio is resolved by downloadRecording.
import {publicRead} from './tunemir.mjs';
import {importSelectArtist,importMetadata,cleanEdition} from './request.mjs';
const API='https://api.deezer.com';
export async function scanArtistCatalog(artist,signal,read=publicRead){
 async function json(path){const u=new URL(path,API);if(u.origin!==API||u.username||u.password)throw Error('Недопустимая ссылка каталога');const d=JSON.parse((await read(u.href,{signal})).bytes.toString('utf8'));if(d.error)throw Error('Каталог временно недоступен');return d;}
 async function pages(path,visit){const seen=new Set();while(path){const u=new URL(path,API).href;if(seen.has(u))throw Error('Каталог повторяет страницу; список неполный');if(seen.size>=10000)throw Error('Каталог слишком большой; список неполный');seen.add(u);const d=await json(u);if(!Array.isArray(d.data))throw Error('Каталог не отдал список');await visit(d.data);path=d.next||null;}}
 const candidates=[];await pages('/search/artist?'+new URLSearchParams({q:artist,limit:'100'}),async rows=>{for(const x of rows)if(x.id&&x.name)candidates.push({name:x.name,url:API+'/artist/'+x.id,id:x.id})});
 const selected=importSelectArtist(candidates,artist);const albums=new Map(),tracks=new Map();let truncated=false;
 await pages('/artist/'+selected.id+'/albums?limit=100',async rows=>{for(const a of rows)if(/^\d+$/.test(String(a.id)))albums.set(String(a.id),a.title||'')});
 for(const [id,albumTitle] of albums){try{await pages('/album/'+id+'/tracks?limit=100',async rows=>{for(const t of rows){if(!t.title||!/^\d+$/.test(String(t.id))||cleanEdition(t.title))continue;const artists=[t.artist,...(t.contributors||[])].filter(Boolean);if(!artists.some(a=>String(a.id)===String(selected.id)))continue;tracks.set(String(t.id),{...importMetadata({title:t.title+(t.title_version&&!t.title.includes(t.title_version)?' '+t.title_version:''),artist:artists.filter((a,i)=>artists.findIndex(b=>b.id===a.id)===i).map(a=>a.name).join(', '),album:t.album?.title||albumTitle}),sourceKey:'catalog:'+t.id,url:'https://www.deezer.com/track/'+t.id,duration:Number(t.duration)||undefined});}})}catch(e){if(signal?.aborted)throw e;truncated=true;}}
 if(!tracks.size)throw Error('Каталог не отдал записи исполнителя');
 return {tracks:[...tracks.values()],truncated,unavailable:0,note:truncated?'Часть альбомов недоступна; каталог неполный.':''};
}
