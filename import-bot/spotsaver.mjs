// Public SpotSaver requests mirror its own form. No account cookies or protection bypasses.
import {publicRead} from './tunemir.mjs';
import {MAX_BYTES} from './core.mjs';
import {ensureMP3} from './audio.mjs';
import {importMetadata,importArtistMatches,cleanEdition} from './request.mjs';
export async function spotsaverMetadata(value,{signal,read=publicRead}={}){
 const input=String(value),isURL=input.startsWith('https://open.spotify.com/');
 const endpoint='https://spotsaver.net/api/spotify/?'+new URLSearchParams(isURL?{url:input}:{q:input});
 const data=JSON.parse((await read(endpoint,{signal})).bytes.toString('utf8'));
 if(data.error||!Array.isArray(data.items))throw Error('SpotSaver не отдал каталог');
 const tracks=data.items.filter(t=>t.title&&t.artist&&!cleanEdition(t.title)&& (isURL||importArtistMatches(t.artist,input))).map(t=>({...importMetadata(t),sourceKey:(isURL&&/^[A-Za-z0-9]{22}$/.test(String(t.id))?'spotify:':'spotsaver:')+t.id,url:isURL?input:undefined,duration:Number(t.duration)||undefined}));
 if(!tracks.length)throw Error('SpotSaver не нашёл записи выбранного исполнителя');
 return {tracks,truncated:data.type!=='track',unavailable:0};
}
export async function downloadSpotsaver(track,selected,{signal,read=publicRead,request=fetch}={}){
 const url=new URL(selected.url),videoId=url.searchParams.get('v');
 if(url.hostname!=='www.youtube.com'||!videoId||!/^[\w-]{11}$/.test(videoId))throw Error('Нужна проверенная запись YouTube');
 const response=await request('https://spotsaver.net/api/download/',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({videoId,candidateIds:[],format:'mp3',title:track.artist+' - '+track.title}),signal:signal?AbortSignal.any([signal,AbortSignal.timeout(90000)]):AbortSignal.timeout(90000)});
 if(!response.ok)throw Error('SpotSaver недоступен (HTTP '+response.status+')');
 const data=await response.json();const target=data.downloadUrl||data.url||data.fileUrl||data.mediaUrl;
 if(!target||data.error)throw Error('SpotSaver не предоставил полный файл');
 const u=new URL(target);if(u.protocol!=='https:'||/preview|scdn\.co/i.test(u.href))throw Error('Превью не импортируется');
 const audio=await read(u.href,{signal,max:MAX_BYTES,referer:'https://spotsaver.net/'});
 if(audio.bytes.length<50000)throw Error('SpotSaver вернул слишком короткий файл');
 return {bytes:await ensureMP3(audio.bytes,{signal}),...importMetadata(track)};
}
