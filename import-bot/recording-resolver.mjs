import {publicRead,parseTuneTracks} from './tunemir.mjs';
import {parseMuzso,parseMuzpace,downloadProvider} from './providers.mjs';
import {downloadSpotsaver} from './spotsaver.mjs';
import {importMetadata,importArtistMatches,recordingKey,cleanEdition} from './request.mjs';
import {recordingTitle} from './downloader.mjs';
import {inspectAudio,validateAudioDuration} from './audio.mjs';
export function sameRecording(candidate,track){
 try{candidate={...candidate,...importMetadata(candidate)}}catch{return false}
 if(cleanEdition(candidate.title)||recordingKey(recordingTitle(candidate.title))!==recordingKey(recordingTitle(track.title)))return false;
 const wanted=String(track.artist||'').split(/\s*(?:,|&|feat\.?|ft\.?)\s*/i).filter(Boolean),credits=String(candidate.artist||'').split(/\s*(?:,|&|feat\.?|ft\.?)\s*/i).filter(Boolean);
 return wanted.some(a=>credits.some(b=>importArtistMatches(a,b)));
}
export async function downloadRecording(track,{signal,read=publicRead,youtube,prepare,providerDownload=downloadProvider,spotsaver=downloadSpotsaver,probe=inspectAudio}={}){
 await prepare?.();
 async function verify(audio){if(audio.bytes){const meta=await probe(audio.bytes,{signal});validateAudioDuration(meta.duration,Number(track.duration)||0);if(track.duration&&Math.abs(meta.duration-track.duration)>Math.max(15,track.duration*.15))throw Error('Длительность найденной записи отличается от оригинала')}return {...audio,...importMetadata(track)}}
 const query=track.artist+' '+track.title;
 const sources=[
  ['https://one.muzso.net/query?'+new URLSearchParams({q:query}),parseMuzso],
  ['https://tunemir.com/index.php?'+new URLSearchParams({do:'search',subaction:'search',story:query,search_start:'1',full_search:'0',result_from:'1'}),(html,url)=>parseTuneTracks(html,url).map(t=>({...t,provider:'tunemir'}))],
  ['https://muzpace.net/search?'+new URLSearchParams({q:query}),parseMuzpace]
 ];
 for(const [url,parse]of sources){
  try{const rows=parse((await read(url,{signal})).bytes.toString('utf8'),url).filter(t=>sameRecording(t,track));
   for(const candidate of rows.slice(0,3)){try{return await verify(await providerDownload(candidate,signal,read))}catch(e){if(signal?.aborted)throw e}}
  }catch(e){if(signal?.aborted)throw e}
 }
 if(!youtube)throw Error('Полная запись не найдена в доступных источниках: '+track.artist+' — '+track.title);
 const selected=await youtube.searchRecording(track,signal);
 try{return await verify(await spotsaver(track,selected,{signal,read}))}catch(e){if(signal?.aborted)throw e}
 const audio=await youtube.download({id:track.jobID||'recording',artist:track.artist},{...selected,duration:track.duration||selected.duration,ordinal:track.ordinal||0},signal);
 return verify(audio);
}
