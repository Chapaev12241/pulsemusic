// Public catalog metadata selections. Audio is resolved separately as a full recording.
import {publicRead} from './tunemir.mjs';
import {importMetadata,cleanEdition} from './request.mjs';
const API='https://api.deezer.com';
function selection(raw){
 let u;try{u=new URL(raw)}catch{return null}
 if(u.protocol!=='https:'||!['deezer.com','www.deezer.com'].includes(u.hostname)||u.username||u.password||u.port)return null;
 const match=u.pathname.match(/^\/(?:[a-z]{2}\/)?(track|playlist|album)\/([1-9]\d{0,19})\/?$/);
 return match?{kind:match[1],id:match[2]}:null;
}
export function supportsCatalogSelection(raw){return !!selection(raw)}
function numericID(value){const id=String(value??'');return /^[1-9]\d{0,19}$/.test(id)?id:null}
function metadata(track,album=''){
 const id=numericID(track?.id);if(!id||typeof track.title!=='string'||!track.title.trim())return null;
 const version=typeof track.title_version==='string'?track.title_version:'';
 const title=track.title+(version&&!track.title.includes(version)?' '+version:'');
 if(cleanEdition(title))return 'clean';
 const credits=[track.artist,...(Array.isArray(track.contributors)?track.contributors:[])].filter(a=>a&&typeof a.name==='string'&&a.name.trim());
 const seen=new Set(),artists=[];for(const credit of credits){const key=numericID(credit.id)||credit.name.toLocaleLowerCase();if(!seen.has(key)){seen.add(key);artists.push(credit.name)}}
 if(!artists.length)return null;
 try{return {...importMetadata({title,artist:artists.join(', '),album:track.album?.title||album}),sourceKey:'catalog:'+id,url:'https://www.deezer.com/track/'+id,duration:Number.isFinite(Number(track.duration))&&Number(track.duration)>0?Number(track.duration):undefined}}catch{return null}
}
export async function scanCatalogSelection(raw,artist='',signal,read=publicRead){
 const target=selection(raw);if(!target)throw Error('Нужна публичная ссылка Deezer на трек, альбом или плейлист');
 async function json(url){let value;try{value=JSON.parse((await read(url,{signal,max:2*1024*1024})).bytes.toString('utf8'))}catch(e){if(signal?.aborted)throw e;throw Error('Каталог не отдал доступные метаданные')}
  if(!value||typeof value!=='object'||value.error)throw Error('Запись или плейлист недоступны в публичном каталоге');return value;
 }
 const rootPath='/'+target.kind+'/'+target.id,root=await json(API+rootPath);
 if(String(root.id??'')!==target.id)throw Error('Каталог вернул другую запись');
 if(target.kind==='track'){
  const track=metadata(root);if(!track)throw Error('Не определены название или исполнитель выбранного трека');if(track==='clean')throw Error('Выбрана clean-версия: она не импортируется');
  return {tracks:[track],truncated:false,unavailable:0};
 }
 const path=rootPath+'/tracks',seenPages=new Set(),tracks=new Map();let next=API+path+'?limit=100',unavailable=0,seenRows=0,truncated=false,lastIndex=-1;
 const expected=Number(root.nb_tracks??root.track_count??root.tracks?.total)||0;
 while(next){
  if(seenPages.size>=10000)throw Error('Каталог содержит больше 10000 страниц; список не завершён');
  let url;try{url=new URL(next,API)}catch{throw Error('Каталог вернул недопустимую страницу')}
  const indexText=url.searchParams.get('index')??'0',limitText=url.searchParams.get('limit')??'100',index=Number(indexText),limit=Number(limitText);
  if(url.origin!==API||url.pathname!==path||url.username||url.password||url.hash||url.searchParams.getAll('index').length>1||url.searchParams.getAll('limit').length>1||!/^\d+$/.test(indexText)||!/^\d+$/.test(limitText)||[...url.searchParams.keys()].some(k=>!['index','limit'].includes(k))||!Number.isSafeInteger(index)||index<0||index<=lastIndex||!Number.isSafeInteger(limit)||limit<1||limit>1000)throw Error('Каталог вернул недопустимую пагинацию');
  if(seenPages.has(url.href))throw Error('Каталог повторяет страницу; список не завершён');seenPages.add(url.href);lastIndex=index;
  let page;try{page=await json(url.href)}catch(e){if(signal?.aborted||!tracks.size)throw e;truncated=true;break}
  if(!Array.isArray(page.data))throw Error('Каталог не отдал список треков');
  seenRows+=page.data.length;
  for(const row of page.data){const track=metadata(row,target.kind==='album'?String(root.title||''):'');if(track==='clean')continue;if(!track){unavailable++;continue}tracks.set(track.sourceKey,track)}
  if(page.next&&typeof page.next!=='string')throw Error('Каталог вернул недопустимую пагинацию');next=page.next||null;
 }
 if(!tracks.size)throw Error('В подборке нет доступных полных описаний треков');
 if(expected>seenRows)truncated=true;
 return {tracks:[...tracks.values()],truncated,unavailable,note:truncated?'Каталог отдал неполный список подборки. Остальные записи пока недоступны.':''};
}
