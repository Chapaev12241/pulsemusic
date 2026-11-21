// Public audio and podcast feeds supplement extractor-specific sites. Every
// network request retains publicRead's DNS pinning and redirect validation.
import {createHash} from 'node:crypto';
import {publicRead,decodeHTML} from './tunemir.mjs';
import {sourceURL} from './network.mjs';
import {MAX_BYTES,previewAudioURL} from './core.mjs';
import {ensureMP3,inspectAudio,validateAudioDuration} from './audio.mjs';
import {cleanEdition,importMetadata} from './request.mjs';

export const OPEN_MEDIA_LIMIT=2000;
const audioPath=u=>/\.(?:mp3|m4a|mp4|aac|flac|ogg|oga|opus|wav|aiff?|web[am])$/i.test(new URL(u).pathname);
export {previewAudioURL};
const plain=s=>decodeHTML(String(s||'').replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g,'$1').replace(/<[^>]*>/g,' ')).replace(/\s+/g,' ').trim();
function attrs(tag){const out={};for(const m of tag.matchAll(/([\w:.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/g))out[m[1].toLowerCase()]=decodeHTML(m[2]??m[3]??m[4]??'');return out}
function text(xml,name){return plain(xml.match(new RegExp('<'+name+'(?:\\s[^>]*)?>([\\s\\S]*?)<\\/'+name+'>','i'))?.[1])}
export function parseMediaDuration(value){
 const number=Number(value);if(Number.isFinite(number)&&number>0)return number;
 const text=String(value||'').trim(),iso=text.match(/^PT(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?$/i);
 if(iso)return Number(iso[1]||0)*3600+Number(iso[2]||0)*60+Number(iso[3]||0);
 if(/^\d{1,3}(?::\d{1,2}){1,2}$/.test(text))return text.split(':').reduce((sum,part)=>sum*60+Number(part),0);
 return undefined;
}
function filenameMetadata(raw,artist='',title=''){
 let filename='';try{filename=decodeURIComponent(new URL(raw).pathname.split('/').pop()||'').replace(/\.[^.]+$/,'').replace(/_/g,' ')}catch{}
 const split=filename.match(/^(.+?)\s+[-–—]\s+(.+)$/);
 return {artist:plain(artist)||(split?split[1]:''),title:plain(title)||(split?split[2]:filename)||'Трек'};
}
function publicLink(raw,base){try{return sourceURL(new URL(decodeHTML(raw),base).href).href}catch{return null}}
export function parseOpenMedia(html,page,artist=''){
 const tracks=[],seen=new Set(),links=[];let feed=false;
 const meta={};for(const m of html.matchAll(/<meta\b[^>]*>/gi)){const a=attrs(m[0]);if(a.content)meta[(a.property||a.name||'').toLowerCase()]=a.content}
 const title=plain(meta['og:title']||html.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1]);
 const author=plain(artist||meta['music:artist']||meta.author||meta['article:author']);
 const add=(raw,info={})=>{const url=publicLink(raw,page);if(!url||previewAudioURL(url)||seen.has(url))return;const metadata=filenameMetadata(url,artist||info.artist||author,info.title||'');if(cleanEdition(metadata.title))return;seen.add(url);tracks.push({url:page,audio:url,provider:'open-media',sourceKey:'open:'+createHash('sha256').update(url).digest('hex'),...metadata,artistOverride:plain(artist)||undefined,album:plain(info.album||''),duration:parseMediaDuration(info.duration)})};
 if(/<(?:rss|feed)\b/i.test(html)){
  feed=true;const channel=html.match(/<channel\b[^>]*>([\s\S]*?)(?:<item\b|<\/channel>)/i)?.[1]||html.split(/<entry\b/i)[0];
  const channelTitle=text(channel,'title'),channelArtist=artist||text(channel,'itunes:author')||text(channel,'dc:creator')||text(channel,'author')||channelTitle;
  for(const item of html.matchAll(/<(?:item|entry)\b[^>]*>([\s\S]*?)<\/(?:item|entry)>/gi)){
   const node=item[1],info={title:text(node,'title'),artist:artist||text(node,'itunes:author')||text(node,'dc:creator')||channelArtist,album:channelTitle,duration:text(node,'itunes:duration')};
   for(const link of node.matchAll(/<(?:enclosure|link|media:content)\b[^>]*>/gi)){const a=attrs(link[0]),url=a.url||a.href;if(url&&(link[0].toLowerCase().startsWith('<enclosure')||a.rel==='enclosure'||a.type?.startsWith('audio/')))add(url,info)}
  }
  for(const link of html.matchAll(/<(?:atom:)?link\b[^>]*>/gi)){const a=attrs(link[0]);if(a.rel==='next'&&a.href)links.push(a.href)}
 }
 for(const m of html.matchAll(/<script\b[^>]*type\s*=\s*["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)){
  let data;try{data=JSON.parse(m[1])}catch{continue}
  function walk(node,depth=0){if(!node||typeof node!=='object'||depth>16)return;if(Array.isArray(node)){node.forEach(x=>walk(x,depth+1));return}
   const kind=[node['@type']].flat().join(' ');if(/AudioObject|MusicRecording|PodcastEpisode/i.test(kind)){
    const people=[node.byArtist||node.author||node.creator].flat().filter(Boolean).map(x=>typeof x==='string'?x:x.name).filter(Boolean).join(', ');
    const urls=[node.contentUrl,node.audio?.contentUrl,...[node.encoding||[]].flat().map(x=>x?.contentUrl),...[node.associatedMedia||[]].flat().map(x=>x?.contentUrl)].filter(x=>typeof x==='string');
    for(const url of urls)add(url,{title:node.name||title,artist:people||author,album:node.inAlbum?.name,duration:node.duration});
   }for(const child of Object.values(node))if(child&&typeof child==='object')walk(child,depth+1)
  }walk(data);
 }
 for(const audio of html.matchAll(/<audio\b([^>]*)>([\s\S]*?)<\/audio>|<audio\b([^>]*)\/>/gi)){
  const a=attrs(audio[1]||audio[3]||''),info={title:a['data-title']||a.title||title,artist:a['data-artist']||author,duration:a['data-duration']};if(a.src)add(a.src,info);
  for(const source of (audio[2]||'').matchAll(/<source\b[^>]*>/gi)){const s=attrs(source[0]);if(s.src&&(!s.type||s.type.startsWith('audio/')))add(s.src,info)}
 }
 for(const link of html.matchAll(/<a\b([^>]*)>([\s\S]*?)<\/a>/gi)){const a=attrs(link[1]),url=a.href&&publicLink(a.href,page);if(!url)continue;if(audioPath(url)||a.type?.startsWith('audio/')){const label=plain(link[2]);add(url,{title:a['data-title']||a.title||(!/^(?:(?:скачать|download|listen|слушать)(?:\s|$)|mp3$|audio$)/i.test(label)?label:''),artist:a['data-artist']||author})}}
 for(const key of ['og:audio:secure_url','og:audio','twitter:player:stream'])if(meta[key])add(meta[key],{title,artist:author});
 for(const link of html.matchAll(/<(?:a|(?:atom:)?link)\b[^>]*>/gi)){const a=attrs(link[0]);if(a.href&&a.rel?.split(/\s+/).includes('next'))links.push(a.href)}
 const next=[];for(const raw of links){const u=publicLink(raw,page);if(u&&new URL(u).origin===new URL(page).origin)next.push(u)}
 return {tracks,next:[...new Set(next)],feed};
}
export async function scanOpenMedia(raw,artist='',signal,read=publicRead){
 const initial=sourceURL(raw).href;if(previewAudioURL(initial))throw Error('Это ссылка на короткий фрагмент, а не полную запись');
 if(audioPath(initial))return {tracks:[{url:initial,audio:initial,provider:'open-media',sourceKey:'open:'+createHash('sha256').update(initial).digest('hex'),...filenameMetadata(initial,artist),artistOverride:plain(artist)||undefined,album:''}],truncated:false,unavailable:0};
 try{const head=await read(initial,{signal,max:MAX_BYTES,method:'HEAD'});if(head.type?.startsWith('audio/'))return {tracks:[{url:initial,audio:head.url||initial,provider:'open-media',sourceKey:'open:'+createHash('sha256').update(initial).digest('hex'),...filenameMetadata(initial,artist),artistOverride:plain(artist)||undefined,album:''}],truncated:false,unavailable:0}}catch(e){if(signal?.aborted)throw e}
 const queue=[initial],visited=new Set(),tracks=new Map();let recognized=false,truncated=false;
 while(queue.length){
  if(visited.size>=100){truncated=true;break}const page=queue.shift();if(visited.has(page))continue;visited.add(page);
  const response=await read(page,{signal,max:2*1024*1024});
  if(response.type?.startsWith('audio/')){recognized=true;tracks.set(page,{url:page,audio:page,provider:'open-media',sourceKey:'open:'+createHash('sha256').update(page).digest('hex'),...filenameMetadata(page,artist),artistOverride:plain(artist)||undefined,album:''});break}
  if(response.bytes.length>2*1024*1024)throw Error('Страница источника слишком большая');
  const parsed=parseOpenMedia(response.bytes.toString('utf8'),response.url||page,artist);recognized ||= parsed.feed||parsed.tracks.length>0;
  for(const track of parsed.tracks){tracks.set(track.sourceKey,track);if(tracks.size>=OPEN_MEDIA_LIMIT){truncated=parsed.next.length>0||queue.length>0||parsed.tracks.at(-1)!==track;break}}
  if(tracks.size>=OPEN_MEDIA_LIMIT)break;
  for(const next of parsed.next)if(!visited.has(next)&&!queue.includes(next))queue.push(next);
 }
 return recognized&&tracks.size?{tracks:[...tracks.values()],truncated,unavailable:0}:null;
}
export function mergeAudioMetadata(track,embedded){return importMetadata({title:embedded.title||track.title,artist:track.artistOverride||embedded.artist||track.artist,album:embedded.album||track.album})}
export async function downloadOpenMedia(track,signal,read=publicRead,{inspect=inspectAudio,convert=ensureMP3}={}){
 if(previewAudioURL(track.audio||track.url))throw Error('Источник отдаёт короткий фрагмент вместо полной записи');
 const response=await read(sourceURL(track.audio||track.url).href,{signal,max:MAX_BYTES,referer:track.url});
 const embedded=await inspect(response.bytes,{signal});validateAudioDuration(embedded.duration,track.duration);
 const bytes=await convert(response.bytes,{signal,force:/audio\/(?:aac|aacp)/i.test(response.type||'')||/\.aac$/i.test(new URL(track.audio||track.url).pathname)});
 try{return {bytes,...mergeAudioMetadata(track,embedded)}}catch{throw Error('Не определён исполнитель. Пришли ссылку вместе с именем исполнителя.')}
}
