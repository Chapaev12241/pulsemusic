import test from 'node:test';
import assert from 'node:assert/strict';
import {supportsCatalogSelection,scanCatalogSelection} from './selection.mjs';
const track=(id,extra={})=>({id,title:'Song '+id,artist:{id:17,name:'Artist'},duration:210,...extra});
const response=data=>({bytes:Buffer.from(JSON.stringify(data))});
test('only canonical HTTPS catalog selection URLs are routed as metadata',()=>{
 for(const value of ['https://www.deezer.com/track/123','https://deezer.com/playlist/456','https://www.deezer.com/ja/album/789'])assert(supportsCatalogSelection(value));
 for(const value of ['http://www.deezer.com/track/123','https://www.deezer.com.evil.test/track/123','https://user@www.deezer.com/track/123','https://www.deezer.com:8080/track/123','https://api.deezer.com/track/123','https://www.deezer.com/artist/123','https://www.deezer.com/track/not-a-number'])assert(!supportsCatalogSelection(value));
});
test('single selected track preserves real credits, version, album and full duration without using preview audio',async()=>{
 const calls=[];const result=await scanCatalogSelection('https://www.deezer.com/track/123','Wrong artist',undefined,async url=>{calls.push(url);return response(track(123,{title:'Selected Song',title_version:'(Live)',contributors:[{id:17,name:'Artist'},{id:18,name:'Guest'}],album:{title:'Album'},preview:'https://preview.example.org/sample.mp3'}))});
 assert.equal(result.tracks.length,1);assert.equal(result.tracks[0].artist,'Artist, Guest');assert.equal(result.tracks[0].title,'Selected Song (Live)');assert.equal(result.tracks[0].album,'Album');assert.equal(result.tracks[0].duration,210);assert.equal(result.tracks[0].sourceKey,'catalog:123');assert.equal(result.tracks[0].url,'https://www.deezer.com/track/123');assert.equal(result.tracks[0].audio,undefined);assert.deepEqual(calls,['https://api.deezer.com/track/123']);
});
test('whole themed playlist traverses pages beyond 20, deduplicates IDs, and excludes clean versions',async()=>{
 const calls=[];const read=async raw=>{const u=new URL(raw);calls.push(raw);if(u.pathname==='/playlist/42')return response({id:42,nb_tracks:46});if(u.searchParams.get('index')==='25')return response({data:[...Array.from({length:20},(_,i)=>track(i+26)),track(1)]});return response({data:Array.from({length:25},(_,i)=>track(i+1,i===3?{title:'Song 4 (Clean Version)'}:{})),next:'https://api.deezer.com/playlist/42/tracks?index=25&limit=25'})};
 const result=await scanCatalogSelection('https://www.deezer.com/playlist/42','',undefined,read);assert.equal(result.tracks.length,44);assert.equal(result.truncated,false);assert.equal(result.unavailable,0);assert(calls.some(x=>x.includes('index=25')));assert(result.tracks.every(x=>!x.title.includes('Clean')));
});
test('album title fallback and repeated version text remain correct',async()=>{
 const result=await scanCatalogSelection('https://www.deezer.com/album/7','',undefined,async url=>response(url.endsWith('/album/7')?{id:7,title:'Album title',nb_tracks:1}:{data:[track(99,{title:'Song (Live)',title_version:'(Live)'})]}));assert.equal(result.tracks[0].album,'Album title');assert.equal(result.tracks[0].title,'Song (Live)');
});
test('untrusted next-page links never reach the transport',async()=>{
 for(const next of ['http://api.deezer.com/playlist/42/tracks?index=25','https://evil.example.org/playlist/42/tracks?index=25','https://api.deezer.com/playlist/43/tracks?index=25','https://api.deezer.com/playlist/42/tracks?index=25&access_token=secret','https://api.deezer.com/playlist/42/tracks?index=0','https://api.deezer.com/playlist/42/tracks?index=25#fragment']){
  let calls=0;await assert.rejects(scanCatalogSelection('https://www.deezer.com/playlist/42','',undefined,async raw=>{calls++;return response(raw.endsWith('/playlist/42')?{id:42}:{data:[track(1)],next})}),/пагинацию/);assert.equal(calls,2);
 }
});
test('failed later pages and a missing advertised tail remain explicitly partial',async()=>{
 let calls=0;const result=await scanCatalogSelection('https://www.deezer.com/playlist/42','',undefined,async raw=>{calls++;if(calls===1)return response({id:42,nb_tracks:40});if(calls===2)return response({data:[track(1)],next:'https://api.deezer.com/playlist/42/tracks?index=1'});throw Error('Provider offline')});assert.equal(result.tracks.length,1);assert.equal(result.truncated,true);assert.match(result.note,/неполный/);
 const missing=await scanCatalogSelection('https://www.deezer.com/playlist/42','',undefined,async raw=>response(raw.endsWith('/playlist/42')?{id:42,nb_tracks:40}:{data:[track(1)]}));assert.equal(missing.truncated,true);
});
test('unavailable root, wrong recording and clean-only selection fail before any download',async()=>{
 await assert.rejects(scanCatalogSelection('https://www.deezer.com/track/123','',undefined,async()=>response({error:{message:'Unavailable'}})),/недоступны/);
 await assert.rejects(scanCatalogSelection('https://www.deezer.com/track/123','',undefined,async()=>response(track(124))),/другую/);
 await assert.rejects(scanCatalogSelection('https://www.deezer.com/track/123','',undefined,async()=>response(track(123,{title:'Song (Clean)'}))),/clean/);
});
