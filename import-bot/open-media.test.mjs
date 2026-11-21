import test from 'node:test';
import assert from 'node:assert/strict';
import {parseOpenMedia,scanOpenMedia,previewAudioURL,mergeAudioMetadata,downloadOpenMedia,parseMediaDuration} from './open-media.mjs';
import {normalizeEntries,MAX_TRACKS,downloadFailure,Downloader,artistSearchEntries} from './downloader.mjs';
import {isMP3,parseAudioProbe,inspectAudio,validateAudioDuration} from './audio.mjs';
import {existsSync} from 'node:fs';

test('public HTML audio and JSON-LD retain artist metadata and deduplicate media',()=>{
 const html=`<meta name="author" content="Artist"><title>Release</title><audio data-title="Song"><source src="/files/Artist%20-%20Song.mp3" type="audio/mpeg"></audio><a href="/files/Artist%20-%20Song.mp3">Download</a><script type="application/ld+json">{"@type":"MusicRecording","name":"Second","byArtist":{"name":"Other"},"encoding":{"@type":"AudioObject","contentUrl":"https://cdn.example.org/second.flac"}}</script>`;
 const result=parseOpenMedia(html,'https://example.org/release');
 assert.equal(result.tracks.length,2);assert.equal(result.tracks[0].artist,'Other');assert.equal(result.tracks[1].title,'Song');assert(result.tracks.every(t=>t.provider==='open-media'));
});
test('source parser refuses private links, previews and non-HTTP protocols',()=>{
 const html='<audio src="http://127.0.0.1/private"></audio><audio src="http://2130706433/private"></audio><audio src="http://localhost/private"></audio><audio src="file:///etc/passwd"></audio><audio src="https://p.scdn.co/mp3-preview/id"></audio><audio src="https://cdn.example.org/full.mp3"></audio>';
 const result=parseOpenMedia(html,'https://example.org/album','Artist');assert.equal(result.tracks.length,1);assert.equal(result.tracks[0].audio,'https://cdn.example.org/full.mp3');assert.equal(previewAudioURL('https://cdn.example.org/preview/song.mp3'),true);
});
test('RSS and Atom enclosures support same-origin next-page traversal only',async()=>{
 const first='<rss><channel><title>Collection</title><itunes:author>Artist</itunes:author><atom:link rel="next" href="/feed?page=2"/><atom:link rel="next" href="http://127.0.0.1/private"/><item><title>Song 1</title><enclosure url="https://cdn.example.org/1.mp3" type="audio/mpeg"/></item></channel></rss>';
 const second='<feed><title>Collection</title><entry><title>Song 2</title><author>Artist</author><link rel="enclosure" href="https://cdn.example.org/2.opus" type="audio/opus"/></entry></feed>';
 const requests=[];const read=async(url,{method}={})=>{requests.push({url,method});return {type:'application/rss+xml',url,bytes:Buffer.from(url.includes('page=2')?second:first)}};
 const result=await scanOpenMedia('https://example.org/feed','Artist',undefined,read);assert.equal(result.tracks.length,2);assert.equal(result.truncated,false);assert.deepEqual(result.tracks.map(x=>x.title),['Song 1','Song 2']);assert(!requests.some(x=>x.url.includes('127.0.0.1')));
});
test('direct audio URLs preserve explicit artist and reject known sample links',async()=>{
 const result=await scanOpenMedia('https://cdn.example.org/music/Artist%20-%20Song.flac','Artist');assert.equal(result.tracks[0].title,'Song');assert.equal(result.tracks[0].artist,'Artist');await assert.rejects(scanOpenMedia('https://p.scdn.co/mp3-preview/id','Artist'),/фрагмент/);
});
test('extractor catalogs no longer stop at250 and explicit artist fallback is carried',()=>{
 const info={extractor_key:'Soundcloud',entries:Array.from({length:300},(_,i)=>({id:String(i),title:'Song '+i,url:'https://soundcloud.com/artist/song-'+i}))};
 const result=normalizeEntries(info,'https://soundcloud.com/artist','Artist');assert.equal(MAX_TRACKS,2000);assert.equal(result.tracks.length,300);assert.equal(result.tracks[0].artist,'Artist');assert.equal(result.truncated,false);const credited=normalizeEntries({extractor_key:'Generic',title:'Song',artist:'Actual credits'},'https://example.org/song','Fallback');assert.equal(credited.tracks[0].artist,'Actual credits');
});
test('downloader diagnostics redact upstream URLs and preserve login/DRM distinction',()=>{
 assert.match(downloadFailure('ERROR DRM https://x.example/token=secret'),/DRM/);assert.match(downloadFailure('Sign in. Cookies https://x.example/token=secret'),/вход/);assert(!downloadFailure('ERROR raw https://x.example?secret=token').includes('secret'));const args=new Downloader('/tmp/pulse-test','http://proxy.invalid').arguments();assert(args.includes('--no-remote-components'));assert(args.includes('--ignore-config'));
});
test('raw AAC ADTS is not mistaken for MPEG Layer audio',()=>{assert.equal(isMP3(Buffer.from([255,241,80,128,0])),false);assert.equal(isMP3(Buffer.from([255,251,144,0])),true)});

test('explicit HTML pagination stays on source origin',()=>{
 const result=parseOpenMedia('<audio src="https://cdn.example.org/a.mp3"></audio><a rel="next nofollow" href="?page=2">More</a><a rel="next" href="https://other.example.org/page">Other</a>','https://example.org/artist','Artist');assert.deepEqual(result.next,['https://example.org/artist?page=2']);
});

test('public platform shortlinks route to canonical metadata sources',async()=>{
 const {resolvePlatformLink}=await import('./platforms.mjs');const calls=[];const result=await resolvePlatformLink('https://spotify.link/example',undefined,async(u,o)=>{calls.push(o.method);return{url:'https://open.spotify.com/track/abc',bytes:Buffer.alloc(0)}});assert.equal(result,'https://open.spotify.com/track/abc');assert.deepEqual(calls,['HEAD']);await assert.rejects(resolvePlatformLink('https://spoti.fi/short',undefined,async()=>({url:'http://127.0.0.1/private'})),/публичный/);
});

test('name-only YouTube fallback keeps exact credits and always reports partial',()=>{
 const entry=(id,title,channel,extra={})=>({id,url:id,ie_key:'Youtube',title,channel,duration:180,...extra});
 const result=artistSearchEntries({entries:[entry('abcdefghij1','Song (Official Audio)','Artist - Topic'),entry('abcdefghij2','Artist - Song','ArtistVEVO'),entry('abcdefghij3','Artist - Other','Label'),entry('abcdefghij4','Song','Other'),entry('abcdefghij5','Artist - Wrong','Label',{artist:'Different'}),entry('abcdefghij6','Artist - Live (Live)','Artist'),entry('abcdefghij7','Artist - Full Album','Artist'),entry('abcdefghij8','Artist - Clean (Clean)','Artist'),entry('abcdefghij9','A - stream','Artist',{is_live:true})]},'Artist');
 assert.equal(result.tracks.length,2);assert.deepEqual(result.tracks.map(t=>t.title),['Song','Other']);assert(result.tracks.every(t=>t.artist==='Artist'));assert.equal(result.truncated,true);assert.match(result.note,/Поиск YouTube, неполная дискография/);
});
test('source-specific partial reason reaches durable job result',async()=>{
 const {processJob}=await import('./runner.mjs');let completed;
 await processJob({id:'fixture',source:'https://example.org',lease:'lease'},{scan:async()=>({tracks:[{sourceKey:'source:1',title:'Song'}],truncated:true,note:'Поиск YouTube, неполная дискография'}),download:async()=>({bytes:Buffer.from('ID3audio'),title:'Song',artist:'Artist'}),request:async(path,token,body)=>{if(path.endsWith('/complete'))completed=body;return {}}});
 assert.equal(completed.status,'partial');assert.match(completed.note,/Поиск YouTube, неполная дискография/);
});

test('local probe tags are authoritative unless artist was explicitly supplied',()=>{
 assert.equal(parseMediaDuration('PT3M20S'),200);assert.equal(parseMediaDuration('01:20:00'),4800);
 const embedded=parseAudioProbe({format:{duration:'200',tags:{TITLE:'Tagged Song',ARTIST:'Tagged Artist',ALBUM:'Tagged Album'}},streams:[{codec_type:'audio',duration:'199.5'}]});
 assert.equal(embedded.duration,199.5);assert.deepEqual(mergeAudioMetadata({title:'uuid',artist:'Website',album:''},embedded),{title:'Tagged Song',artist:'Tagged Artist',album:'Tagged Album'});assert.equal(mergeAudioMetadata({title:'uuid',artist:'Website',artistOverride:'Chosen Artist'},embedded).artist,'Chosen Artist');
});
test('direct MP3 inspection uses only a private local file and cleans it',async()=>{
 let input;const metadata=await inspectAudio(Buffer.from('ID3audio'),{ffmpeg:'/fake/ffmpeg',ensureReady:async()=>{},probe:async(executable,args,options)=>{assert.equal(executable,'/fake/ffprobe');assert.equal(args[args.indexOf('-protocol_whitelist')+1],'file,pipe');assert.deepEqual(Object.keys(options.env).sort(),['LANG','PATH']);input=args.at(-1);assert(existsSync(input));return {stdout:JSON.stringify({format:{duration:'200',tags:{artist:'Artist',title:'Song'}}})}}});assert.equal(metadata.artist,'Artist');assert(!existsSync(input));
});
test('direct files cannot bypass clip and 30-minute duration checks',async()=>{
 const track={url:'https://cdn.example.org/uuid.mp3',audio:'https://cdn.example.org/uuid.mp3',title:'uuid',artist:'Unknown',duration:200};const read=async()=>({bytes:Buffer.from('ID3audio'),type:'audio/mpeg'});let converted=false;
 await assert.rejects(downloadOpenMedia(track,undefined,read,{inspect:async()=>({duration:30,title:'Song',artist:'Artist'}),convert:async()=>{converted=true;return Buffer.alloc(0)}}),/короткий фрагмент/);assert.equal(converted,false);
 await assert.rejects(downloadOpenMedia({...track,duration:0},undefined,read,{inspect:async()=>({duration:3600,title:'Song',artist:'Artist'}),convert:async()=>Buffer.alloc(0)}),/30 минут/);assert.throws(()=>validateAudioDuration(NaN),/длительность/);
 const result=await downloadOpenMedia(track,undefined,read,{inspect:async()=>({duration:200,title:'Embedded Song',artist:'Embedded Artist',album:''}),convert:async bytes=>bytes});assert.equal(result.title,'Embedded Song');assert.equal(result.artist,'Embedded Artist');
});
