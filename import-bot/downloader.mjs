import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync,chmodSync,readdirSync,realpathSync,lstatSync} from 'node:fs';
import {join,dirname,sep} from 'node:path';
import {privateDirectory,MAX_BYTES} from './core.mjs';
import {sourceURL} from './network.mjs';

export const MAX_TRACKS=250;
export function tools(directory){return {yt:process.env.PULSE_YTDLP||join(directory,'runtime','yt-dlp'),ffmpeg:process.env.PULSE_FFMPEG||'/usr/bin/ffmpeg'}}
export function runProcess(executable,args,{signal,timeout=120000,cwd,env}={}){
  return new Promise((resolve,reject)=>{
    if(signal?.aborted){reject(new Error('Задание отменено'));return}
    const child=spawn(executable,args,{cwd,env,stdio:['ignore','pipe','pipe'],detached:process.platform!=='win32'});let stdout='',stderr='',finished=false,timedOut=false;
    const kill=()=>{try{if(process.platform==='win32')child.kill();else process.kill(-child.pid,'SIGTERM')}catch{};const timer=setTimeout(()=>{try{if(process.platform==='win32')child.kill('SIGKILL');else process.kill(-child.pid,'SIGKILL')}catch{}},2000);timer.unref()};
    const timer=setTimeout(()=>{timedOut=true;kill()},timeout);timer.unref();const cancel=()=>kill();signal?.addEventListener('abort',cancel,{once:true});
    const done=(error)=>{if(finished)return;finished=true;clearTimeout(timer);signal?.removeEventListener('abort',cancel);error?reject(error):resolve({stdout,stderr})};
    child.stdout.on('data',data=>{stdout+=data;if(stdout.length>8*1024*1024){kill();done(new Error('Слишком большой ответ источника'))}});child.stderr.on('data',data=>{stderr=(stderr+data).slice(-32000)});
    child.on('error',e=>done(new Error(e.code==='ENOENT'?'Загрузчик не установлен':e.message)));child.on('close',code=>done(signal?.aborted?new Error('Задание отменено'):timedOut?new Error('Источник слишком долго отвечает'):code!==0?new Error(stderr.trim()||'Источник не отдал аудио'):null));
  });
}
function childEnvironment(directory,proxy){const env={PATH:dirname(process.execPath)+':'+join(directory,'runtime')+':/usr/local/bin:/usr/bin:/bin',LANG:'en_US.UTF-8'};if(proxy){env.http_proxy=proxy;env.https_proxy=proxy;env.HTTP_PROXY=proxy;env.HTTPS_PROXY=proxy}return env}
export function normalizeEntries(info,input,override='',limit=MAX_TRACKS){
  const flat=[];let unavailable=0;function visit(value,depth=0){if(!value){unavailable++;return}if(Array.isArray(value.entries)&&depth<5){for(const e of value.entries)visit(e,depth+1)}else flat.push(value)}visit(info);
  const seen=new Set(),tracks=[];
  for(const entry of flat){let value=entry.webpage_url||entry.original_url||entry.url||input;const extractor=entry.ie_key||entry.extractor_key||info.extractor_key||'Generic';if(/youtube/i.test(extractor)&&/^[\w-]{11}$/.test(value))value='https://www.youtube.com/watch?v='+value;
    if(flat.length===1&&!entry.webpage_url&&!Array.isArray(info.entries))value=input;
    let url;try{url=sourceURL(new URL(value,input).href)}catch{unavailable++;continue}
    const sourceKey=/generic/i.test(extractor)?'url:'+createHash('sha256').update(url.href).digest('hex'):extractor+':'+url.hostname+':'+String(entry.id||createHash('sha256').update(url.href).digest('hex'));
    if(seen.has(sourceKey))continue;seen.add(sourceKey);tracks.push({url:url.href,sourceKey,title:String(entry.track||entry.title||entry.id||'Трек').slice(0,120),artist:String(override||entry.artist||entry.creator||entry.uploader||info.artist||info.uploader||'Без исполнителя').slice(0,80),album:String(entry.album||info.album||'').slice(0,120)});
  }
  return {tracks:tracks.slice(0,limit),truncated:tracks.length>limit,unavailable};
}
export class Downloader {
  constructor(directory,proxy){this.directory=directory;this.proxy=proxy;this.tools=tools(directory)}
  arguments(){return ['--ignore-config','--no-cache-dir','--no-warnings','--socket-timeout','20','--retries','2','--fragment-retries','2','--proxy',this.proxy,'--js-runtimes','node:'+process.execPath]}
  async scan(url,artist,signal){sourceURL(url);const result=await runProcess(this.tools.yt,[...this.arguments(),'--flat-playlist','--ignore-errors','--playlist-end',String(MAX_TRACKS+1),'--dump-single-json','--skip-download','--',url],{signal,timeout:120000,env:childEnvironment(this.directory,this.proxy)});let data;try{data=JSON.parse(result.stdout.trim())}catch{throw Error('Не удалось прочитать список треков с этой страницы')};const normalized=normalizeEntries(data,url,artist);if(!normalized.tracks.length)throw Error('На странице не найдено доступных треков');return normalized}
  async download(job,track,signal){
    const folder=privateDirectory(join(this.directory,'media',job.id,String(track.ordinal)));sourceURL(track.url);
    const result=await runProcess(this.tools.yt,[...this.arguments(),'--no-playlist','--no-progress','--quiet','--max-filesize','50M','--match-filters','!is_live & duration <=? 1800','-f','bestaudio/best','--extract-audio','--audio-format','mp3','--audio-quality','0','--ffmpeg-location',this.tools.ffmpeg,'--postprocessor-args','ExtractAudio+ffmpeg_i:-protocol_whitelist file,pipe','--write-info-json','--paths',folder,'--output','audio.%(ext)s','--print','after_move:PULSE_FILE:%(filepath)j','--',track.url],{signal,timeout:240000,cwd:folder,env:childEnvironment(this.directory,this.proxy)});
    const marker=result.stdout.split('\n').filter(x=>x.startsWith('PULSE_FILE:')).at(-1);if(!marker)throw Error('Трек пропущен: эфир, слишком длинный файл или размер больше 50 МБ');let path;try{path=JSON.parse(marker.slice(11))}catch{throw Error('Не удалось получить аудиофайл')}
    const actual=realpathSync(path),root=realpathSync(folder)+sep;if(!actual.startsWith(root)||!lstatSync(path).isFile()||lstatSync(path).isSymbolicLink()||!actual.endsWith('.mp3'))throw Error('Загрузчик вернул недопустимый файл');const size=lstatSync(actual).size;if(!size||size>MAX_BYTES)throw Error('После обработки трек превышает 50 МБ');chmodSync(actual,0o600);
    let meta={};try{const name=readdirSync(folder).find(x=>x.endsWith('.info.json'));if(name)meta=JSON.parse(readFileSync(join(folder,name),'utf8'))}catch{}
    return {file:actual,title:String(meta.track||meta.title||track.title).slice(0,120),artist:String(job.artist||meta.artist||meta.creator||meta.uploader||track.artist).slice(0,80),album:String(meta.album||track.album||'').slice(0,120)};
  }
}
