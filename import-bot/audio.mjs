import {mkdtempSync,writeFileSync,readFileSync,rmSync,statSync} from 'node:fs';
import {join,dirname} from 'node:path';import {tmpdir} from 'node:os';
import {runProcess} from './downloader.mjs';import {MAX_BYTES} from './core.mjs';
export function isMP3(bytes){return bytes.length&&(bytes.subarray(0,3).toString()==='ID3'||bytes[0]===255&&(bytes[1]&224)===224&&(bytes[1]&6)!==0)}
let ready;
async function ffmpegReady(path){if(ready===path)return;const env={PATH:'/usr/local/bin:/usr/bin:/bin',LANG:'C.UTF-8'};try{await runProcess(path,['-version'],{env})}catch(e){if(process.platform!=='linux'||process.env.GITHUB_ACTIONS!=='true')throw Error('Для преобразования аудио требуется ffmpeg');await runProcess('/usr/bin/sudo',['/usr/bin/apt-get','update'],{env,timeout:120000});await runProcess('/usr/bin/sudo',['/usr/bin/apt-get','install','-y','ffmpeg'],{env,timeout:180000});await runProcess(path,['-version'],{env})}ready=path}
export async function ensureMP3(bytes,{signal,ffmpeg=process.env.PULSE_FFMPEG||'/usr/bin/ffmpeg',force=false}={}){if(!bytes.length||bytes.length>MAX_BYTES)throw Error('Размер аудио должен быть не больше 50 МБ');if(isMP3(bytes)&&!force)return bytes;const head=bytes.subarray(0,16).toString('latin1');if(head.slice(4,8)!=='ftyp'&&!head.startsWith('OggS')&&!head.startsWith('fLaC')&&!head.startsWith('RIFF')&&!head.startsWith('FORM')&&!head.startsWith('ID3')&&!(bytes[0]===255&&(bytes[1]&246)===240)&&!bytes.subarray(0,4).equals(Buffer.from([0x1a,0x45,0xdf,0xa3])))throw Error('Источник не отдал аудио');await ffmpegReady(ffmpeg);const folder=mkdtempSync(join(tmpdir(),'pulse-audio-'));try{const input=join(folder,'input.bin'),output=join(folder,'output.mp3');writeFileSync(input,bytes,{mode:0o600});await runProcess(ffmpeg,['-nostdin','-hide_banner','-loglevel','error','-protocol_whitelist','file,pipe','-i',input,'-map','0:a:0','-vn','-c:a','libmp3lame','-q:a','2',output],{signal,timeout:240000,env:{PATH:'/usr/bin:/bin',LANG:'C.UTF-8'}});if(statSync(output).size>MAX_BYTES)throw Error('После преобразования аудио больше 50 МБ');const mp3=readFileSync(output);if(!isMP3(mp3))throw Error('Не удалось получить MP3');return mp3}finally{rmSync(folder,{recursive:true,force:true})}}

// Source-file tags are read before conversion, so opaque CDN filenames do not
// replace the artist/title already present in the recording itself.
export function parseAudioProbe(value){
 const data=typeof value==='string'?JSON.parse(value):value;
 const stream=(data?.streams||[]).find(s=>s.codec_type==='audio')||(data?.streams||[])[0]||{};
 const tags=Object.fromEntries(Object.entries({...data?.format?.tags,...stream.tags}).map(([k,v])=>[k.toLowerCase(),String(v).normalize('NFKC').trim()]));
 return {title:tags.title||'',artist:tags.artist||tags.album_artist||tags.albumartist||'',album:tags.album||'',duration:Number(stream.duration)||Number(data?.format?.duration)||0};
}
export function validateAudioDuration(duration,expected=0){
 if(!Number.isFinite(duration)||duration<=0)throw Error('Не удалось прочитать длительность аудио');
 if(duration>1805)throw Error('Запись длиннее 30 минут. Пришли отдельный трек.');
 if(Number(expected)>45&&duration<Number(expected)*.75)throw Error('Источник отдал короткий фрагмент вместо полной записи');
}
export async function inspectAudio(bytes,{signal,ffmpeg=process.env.PULSE_FFMPEG||'/usr/bin/ffmpeg',probe=runProcess,ensureReady=ffmpegReady}={}){
 if(!bytes.length||bytes.length>MAX_BYTES)throw Error('Размер аудио должен быть не больше 50 МБ');
 await ensureReady(ffmpeg);const folder=mkdtempSync(join(tmpdir(),'pulse-probe-'));
 try{
  const input=join(folder,'source.bin');writeFileSync(input,bytes,{mode:0o600});
  const ffprobe=join(dirname(ffmpeg),'ffprobe');
  const result=await probe(ffprobe,['-v','error','-protocol_whitelist','file,pipe','-show_format','-show_streams','-of','json',input],{signal,timeout:30000,env:{PATH:'/usr/local/bin:/usr/bin:/bin',LANG:'C.UTF-8'}});
  let metadata;try{metadata=parseAudioProbe(result.stdout)}catch{throw Error('Не удалось прочитать метаданные аудио')}
  validateAudioDuration(metadata.duration);return metadata;
 }finally{rmSync(folder,{recursive:true,force:true})}
}
