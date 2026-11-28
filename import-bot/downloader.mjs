import {cleanEdition,recordingKey,importArtistKey,importArtistMatches} from './request.mjs';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync,chmodSync,readdirSync,realpathSync,lstatSync,rmSync} from 'node:fs';
import {join,dirname,sep} from 'node:path';
import {privateDirectory,MAX_BYTES,previewAudioURL} from './core.mjs';
import {sourceURL} from './network.mjs';

export const MAX_TRACKS=2000;
export const YTDLP_VERSION='2026.10.26';
export function tools(directory){const ffmpeg=process.env.PULSE_FFMPEG||'/usr/bin/ffmpeg';return {yt:process.env.PULSE_YTDLP||join(directory,'runtime','yt-dlp'),ffmpeg,ffprobe:join(dirname(ffmpeg),'ffprobe')}}
export function runProcess(executable,args,{signal,timeout=120000,cwd,env}={}){
  return new Promise((resolve,reject)=>{
    if(signal?.aborted){reject(new Error('Задание отменено'));return}
    const child=spawn(executable,args,{cwd,env,stdio:['ignore','pipe','pipe'],detached:process.platform!=='win32'});let stdout='',stderr='',finished=false,timedOut=false;
    const kill=()=>{try{if(process.platform==='win32')child.kill();else process.kill(-child.pid,'SIGTERM')}catch{};const timer=setTimeout(()=>{try{if(process.platform==='win32')child.kill('SIGKILL');else process.kill(-child.pid,'SIGKILL')}catch{}},2000);timer.unref()};
    const timer=setTimeout(()=>{timedOut=true;kill()},timeout);timer.unref();const cancel=()=>kill();signal?.addEventListener('abort',cancel,{once:true});
    const done=(error)=>{if(finished)return;finished=true;clearTimeout(timer);signal?.removeEventListener('abort',cancel);error?reject(error):resolve({stdout,stderr})};
    child.stdout.on('data',data=>{stdout+=data;if(stdout.length>8*1024*1024){kill();done(new Error('Слишком большой ответ источника'))}});child.stderr.on('data',data=>{stderr=(stderr+data).slice(-32000)});
    child.on('error',e=>done(new Error(e.code==='ENOENT'?'Загрузчик не установлен':e.message)));child.on('close',code=>done(signal?.aborted?new Error('Задание отменено'):timedOut?new Error('Источник слишком долго отвечает'):code!==0?new Error(downloadFailure(stderr)):null));
  });
}
export function downloadFailure(value){
 const message=String(value||'');
 if(/max.filesize|larger than|max.*file.*size/i.test(message))return 'Файл превышает ограничение 50 МБ';
 if(/drm|protected content|encrypted (?:media|stream)/i.test(message))return 'Источник защищён DRM: нужна открытая аудиоверсия или исходный файл';
 if(/sign in|login required|cookies|private video|members.only|authentication|premium|paywall/i.test(message))return 'Источник требует вход или подписку. Пришли публичную ссылку или исходный файл';
 if(/captcha|confirm you.re not a bot|cloudflare|http error (?:403|429)|rate.limit/i.test(message))return 'Источник ограничил загрузку. Повтори позже или выбери другую ссылку';
 if(/not available in your country|geo.restrict|geographic/i.test(message))return 'Запись недоступна в регионе загрузчика';
 if(/unsupported url|no suitable extractor/i.test(message))return 'Загрузчик пока не поддерживает эту страницу. Попробуй прямую аудиоссылку или RSS';
 if(/not available|video unavailable|removed|not found|http error 404/i.test(message))return 'Запись удалена или недоступна';
 return 'Источник не отдал полную аудиозапись. Попробуй другую публичную ссылку';
}
function childEnvironment(directory,proxy){const env={PATH:dirname(process.execPath)+':'+join(directory,'runtime')+':/usr/local/bin:/usr/bin:/bin',LANG:'en_US.UTF-8'};if(proxy){env.http_proxy=proxy;env.https_proxy=proxy;env.HTTP_PROXY=proxy;env.HTTPS_PROXY=proxy}return env}
export function normalizeEntries(info,input,override='',limit=MAX_TRACKS){
  const flat=[];let unavailable=0;function visit(value,depth=0){if(!value){unavailable++;return}if(Array.isArray(value.entries)&&depth<5){for(const e of value.entries)visit(e,depth+1)}else flat.push(value)}visit(info);
  const seen=new Set(),tracks=[];
  for(const entry of flat){if(cleanEdition(entry.title)){unavailable++;continue}let value=entry.webpage_url||entry.original_url||entry.url||input;const extractor=entry.ie_key||entry.extractor_key||info.extractor_key||'Generic';if(/youtube/i.test(extractor)&&/^[\w-]{11}$/.test(value))value='https://www.youtube.com/watch?v='+value;
    if(flat.length===1&&!entry.webpage_url&&!Array.isArray(info.entries))value=input;
    let url;try{url=sourceURL(new URL(value,input).href);if(previewAudioURL(url.href))throw Error('preview')}catch{unavailable++;continue}
    const sourceKey=/generic/i.test(extractor)?'url:'+createHash('sha256').update(url.href).digest('hex'):extractor+':'+url.hostname+':'+String(entry.id||createHash('sha256').update(url.href).digest('hex'));
    if(seen.has(sourceKey))continue;seen.add(sourceKey);tracks.push({url:url.href,sourceKey,title:String(entry.track||entry.title||entry.id||'Трек').slice(0,120),artist:String(entry.artist||entry.creator||info.artist||override||entry.uploader||info.uploader||'Без исполнителя').slice(0,80),album:String(entry.album||info.album||'').slice(0,120),duration:Number(entry.duration)||undefined,provider:extractor});
  }
  return {tracks:tracks.slice(0,limit),truncated:tracks.length>limit,unavailable};
}
export function artistSearchEntries(info,artist){
 const entries=[],seen=new Set();
 const channelName=value=>String(value||'').replace(/\s*[-–—]\s*Topic$|VEVO$|\s*(?:[-–—]\s*)?(?:Official(?:\s+(?:YouTube\s+)?Channel)?|Официальный\s+канал)\s*$/i,'').trim();
 for(const item of (info.entries||[]).slice(0,100)){
  if(!item||item.is_live||item.was_live||['is_live','is_upcoming','post_live'].includes(item.live_status)||cleanEdition(item.title)||Number(item.duration)>1800)continue;
  const original=String(item.title||item.track||'');
  if(/\b(?:mix|megamix|full album|dj set|live stream|live concert|compilation|playlist)\b|\((?:live|концерт)[^)]*\)|\[(?:live|концерт)[^\]]*\]|(?:сборник|альбом целиком|прямой эфир)/iu.test(original))continue;
  const prefix=original.match(/^(.+?)\s+[-–—]\s+(.+)$/),explicit=[item.artist,item.creator,...(Array.isArray(item.artists)?item.artists:[])].filter(x=>typeof x==='string'&&x.trim());
  const explicitMatch=explicit.some(name=>importArtistMatches(name,artist)||name.split(/\s*(?:,|&|feat\.?|ft\.?)\s*/i).some(x=>importArtistMatches(x,artist)));
  const channel=channelName(item.channel||item.uploader),prefixMatch=prefix&&importArtistMatches(prefix[1],artist);
  if(explicit.length?!explicitMatch:!importArtistMatches(channel,artist)&&!prefixMatch)continue;
  const credit=explicit[0]||(prefixMatch?prefix[1]:channel);
  const title=String(item.track||(prefixMatch?prefix[2]:original)).replace(/\((?:official[^)]*|audio|lyrics?|explicit|uncensored|hd|4k)\)|\[(?:official[^\]]*|audio|lyrics?|explicit|uncensored|hd|4k)\]/gi,'').trim();
  if(!title||cleanEdition(title))continue;
  const key=importArtistKey(credit)+'|'+recordingKey(title);if(seen.has(key))continue;seen.add(key);entries.push({...item,artist:credit,title,track:title});
 }
 const query='https://www.youtube.com/results?search_query='+encodeURIComponent(artist+' official audio');
 const normalized=normalizeEntries({extractor_key:'Youtube',entries},query);
 return {...normalized,truncated:true,note:'Поиск YouTube, неполная дискография: найдено '+normalized.tracks.length+' подходящих записей. Полный каталог не подтверждён.'};
}
export function recordingTitle(value){return String(value||'').normalize('NFKC').replace(/\((?:feat\.?|ft\.?)\s+[^)]*\)|\[(?:feat\.?|ft\.?)\s+[^\]]*\]/gi,'').replace(/\((?:премьера[^)]*|официальн[^)]*|клип[^)]*|текст песни[^)]*)\)|\[(?:премьера[^\]]*|официальн[^\]]*|клип[^\]]*|текст песни[^\]]*)\]/gi,'').replace(/\((?:official[^)]*|audio[^)]*|lyrics?[^)]*|visuali[sz]er[^)]*|music video|mv|pv|hd|4k|explicit|uncensored|(?:\d{4}\s*)?remaster(?:ed)?[^)]*|prod\.?[^)]*)\)|\[(?:official[^\]]*|audio[^\]]*|lyrics?[^\]]*|visuali[sz]er[^\]]*|music video|mv|pv|hd|4k|explicit|uncensored|(?:\d{4}\s*)?remaster(?:ed)?[^\]]*|prod\.?[^\]]*)\]/gi,'').replace(/\s+(?:feat\.?|ft\.?)\s+.*$/i,'').replace(/\s*[-–—]?\s*(?:official (?:music )?(?:video|audio)|lyrics?|visuali[sz]er|\d{4} remaster(?:ed)?)\s*$/i,'').trim()}
export function recordingCandidates(entries,track){
 const artists=String(track.artist||'').split(/\s*(?:,|&|feat\.?|ft\.?)\s*/i).filter(Boolean);
 const isArtist=value=>String(value||'').split(/\s*(?:,|&|feat\.?|ft\.?)\s*/i).some(credit=>artists.some(artist=>importArtistMatches(credit.replace(/\s*[-–—]?\s*Topic$|VEVO$|\s*[-–—]?\s*Official(?: Channel)?$/i,'').trim(),artist)));
 const wanted=recordingKey(recordingTitle(track.title));
 return entries.filter(x=>{
  if(!x||!/^[\w-]{11}$/.test(String(x.id))||cleanEdition(x.title)||x.is_live||x.was_live||['is_live','is_upcoming','post_live'].includes(x.live_status))return false;
  const duration=Number(x.duration)||0;if(duration>1800||track.duration&&duration&&Math.abs(track.duration-duration)>Math.max(12,track.duration*.12))return false;
  const title=recordingTitle(x.track||x.title),parts=title.match(/^(.+?)\s+[-–—]\s+(.+)$/);
  let key=recordingKey(title),titleCredit=false;
  if(parts){const left=isArtist(parts[1])||parts[1].split(/\s*(?:,|&|feat\.?|ft\.?)\s*/i).some(isArtist),right=isArtist(parts[2]);if(left){key=recordingKey(parts[2]);titleCredit=true}else if(right){key=recordingKey(parts[1]);titleCredit=true}}
  if(key!==wanted){const compact=recordingKey(title);titleCredit=artists.some(a=>compact===importArtistKey(a)+wanted||compact===wanted+importArtistKey(a));if(!titleCredit)return false;key=wanted}
  const explicit=[x.artist,x.creator,...(Array.isArray(x.artists)?x.artists:[])].filter(Boolean);
  const credit=explicit.some(isArtist)||isArtist(x.channel||x.uploader)||titleCredit;
  return key===wanted&&credit;
 }).sort((a,b)=>(/official|topic|vevo/i.test((b.channel||b.uploader||'')+' '+b.title)?1:0)-(/official|topic|vevo/i.test((a.channel||a.uploader||'')+' '+a.title)?1:0));
}
export class Downloader {
  constructor(directory,proxy,execute=runProcess){this.directory=directory;this.proxy=proxy;this.tools=tools(directory);this.execute=execute}
  arguments(){return ['--ignore-config','--no-cache-dir','--no-warnings','--no-remote-components','--socket-timeout','20','--retries','2','--fragment-retries','2','--proxy',this.proxy,'--js-runtimes','node:'+process.execPath]}
  async scan(url,artist,signal){sourceURL(url);const result=await runProcess(this.tools.yt,[...this.arguments(),'--flat-playlist','--ignore-errors','--playlist-end',String(MAX_TRACKS+1),'--dump-single-json','--skip-download','--',url],{signal,timeout:120000,env:childEnvironment(this.directory,this.proxy)});let data;try{data=JSON.parse(result.stdout.trim())}catch{throw Error('Не удалось прочитать список треков с этой страницы')};const normalized=normalizeEntries(data,url,artist);if(!normalized.tracks.length)throw Error('На странице не найдено доступных треков');return normalized}
  async searchArtist(artist,signal){
    const result=await runProcess(this.tools.yt,[...this.arguments(),'--flat-playlist','--dump-single-json','--skip-download','--','ytsearch100:'+artist+' official audio'],{signal,timeout:120000,env:childEnvironment(this.directory,this.proxy)});
    let info;try{info=JSON.parse(result.stdout)}catch{throw Error('Не удалось прочитать результаты поиска YouTube')}
    const found=artistSearchEntries(info,artist);if(!found.tracks.length)throw Error('В поиске YouTube нет точных совпадений исполнителя');return found;
  }
  async searchRecording(track,signal){
    const artists=String(track.artist||'').split(/\s*(?:,|&|feat\.?|ft\.?)\s*/i).filter(Boolean);
    const checked=new Set();
    const queries=[...new Set([track.artist+' '+track.title,...artists.map(a=>a+' '+track.title+' audio'),track.title+' '+track.artist])].slice(0,3);
    for(const query of queries){
      const result=await this.execute(this.tools.yt,[...this.arguments(),'--flat-playlist','--dump-single-json','--skip-download','--','ytsearch15:'+query],{signal,timeout:120000,env:childEnvironment(this.directory,this.proxy)});
      let data;try{data=JSON.parse(result.stdout)}catch{throw Error('Не удалось прочитать результаты поиска YouTube')}
      let chosen=recordingCandidates(data.entries||[],track)[0];
      if(!chosen){
        const possible=(data.entries||[]).filter(x=>x&&/^[\w-]{11}$/.test(String(x.id))&&!cleanEdition(x.title)&&recordingKey(recordingTitle(x.title))===recordingKey(recordingTitle(track.title)));
        for(const candidate of possible){
          if(checked.size>=3)break;if(checked.has(candidate.id))continue;checked.add(candidate.id);
          try{
            const details=await this.execute(this.tools.yt,[...this.arguments(),'--no-playlist','--dump-single-json','--skip-download','--','https://www.youtube.com/watch?v='+candidate.id],{signal,timeout:90000,env:childEnvironment(this.directory,this.proxy)});
            const full=JSON.parse(details.stdout);chosen=recordingCandidates([{...candidate,...full}],track)[0];if(chosen)break;
          }catch(e){if(signal?.aborted)throw e}
        }
      }
      if(chosen)return {url:'https://www.youtube.com/watch?v='+chosen.id,title:track.title,artist:track.artist,album:track.album||'',duration:track.duration||Number(chosen.duration)||undefined,sourceKey:'youtube:'+chosen.id};
    }
    throw Error('Полная запись пока не найдена: '+track.artist+' — '+track.title+'. Пришли прямую ссылку на нужную запись.');
  }
  async download(job,track,signal){
    const folder=privateDirectory(join(this.directory,'media',job.id,String(track.ordinal)));try{sourceURL(track.url);if(previewAudioURL(track.url))throw Error('Это короткий фрагмент, а не полная запись');
    const result=await runProcess(this.tools.yt,[...this.arguments(),'--no-playlist','--downloader','native','--downloader','dash,m3u8:native','--no-progress','--quiet','--max-filesize','50M','--match-filters','!is_live & duration <=? 1800','-f','bestaudio[protocol^=http]/bestaudio[protocol=m3u8_native]/best[protocol^=http]/best[protocol=m3u8_native]','--extract-audio','--audio-format','mp3','--audio-quality','0','--ffmpeg-location',this.tools.ffmpeg,'--postprocessor-args','ExtractAudio+ffmpeg_i:-protocol_whitelist file,pipe','--write-info-json','--paths',folder,'--output','audio.%(ext)s','--print','after_move:PULSE_FILE:%(filepath)j','--',track.url],{signal,timeout:240000,cwd:folder,env:childEnvironment(this.directory,this.proxy)});
    const marker=result.stdout.split('\n').filter(x=>x.startsWith('PULSE_FILE:')).at(-1);if(!marker)throw Error('Трек пропущен: эфир, слишком длинный файл или размер больше 50 МБ');let path;try{path=JSON.parse(marker.slice(11))}catch{throw Error('Не удалось получить аудиофайл')}
    const actual=realpathSync(path),root=realpathSync(folder)+sep;if(!actual.startsWith(root)||!lstatSync(path).isFile()||lstatSync(path).isSymbolicLink()||!actual.endsWith('.mp3'))throw Error('Загрузчик вернул недопустимый файл');const size=lstatSync(actual).size;if(!size||size>MAX_BYTES)throw Error('После обработки трек превышает 50 МБ');chmodSync(actual,0o600);
    let meta={};try{const name=readdirSync(folder).find(x=>x.endsWith('.info.json'));if(name)meta=JSON.parse(readFileSync(join(folder,name),'utf8'))}catch{}
    const probe=await runProcess(this.tools.ffprobe,['-v','error','-protocol_whitelist','file,pipe','-show_entries','format=duration','-of','json',actual],{signal,timeout:30000,env:childEnvironment(this.directory)});
    let actualDuration;try{actualDuration=Number(JSON.parse(probe.stdout).format?.duration)}catch{}
    if(!Number.isFinite(actualDuration)||actualDuration<=0)throw Error('Не удалось прочитать длительность аудио');
    const expected=Number(track.duration||meta.duration)||0;
    if(expected>45&&actualDuration<expected*.75)throw Error('Источник отдал короткий фрагмент вместо полной записи');
    if(actualDuration>1805)throw Error('Запись длиннее 30 минут. Пришли отдельный трек.');
    let title=String(meta.track||meta.title||track.title),artist=String(meta.artist||meta.creator||track.artist||job.artist||meta.uploader);if(/(?:youtube\.com|youtu\.be)/i.test(track.url)){artist=artist.replace(/\s*-\s*Topic$|VEVO$/i,'').trim();const parts=title.match(/^(.+?)\s+[-–—]\s+(.+)$/);if(!meta.artist&&parts){artist=parts[1];title=parts[2]}title=title.replace(/\((?:official[^)]*|audio|lyrics?|hd|4k)\)|\[(?:official[^\]]*|audio|lyrics?|hd|4k)\]/gi,'').trim()}if(cleanEdition(title))throw Error('Источник отдаёт только clean-версию');return {file:actual,title:title.slice(0,120),artist:artist.slice(0,80),album:String(meta.album||track.album||'').slice(0,120),cleanup:()=>rmSync(folder,{recursive:true,force:true})};
    }catch(e){rmSync(folder,{recursive:true,force:true});throw e}
  }
}
