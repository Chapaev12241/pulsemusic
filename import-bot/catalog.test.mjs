import test from 'node:test';
import assert from 'node:assert/strict';
import {scanArtistCatalog} from './catalog.mjs';
test('artist catalog traverses every album and track page beyond the 20 search hits',async()=>{
 const seen=[];const read=async raw=>{const u=new URL(raw);seen.push(u.href);let d;
 if(u.pathname==='/search/artist')d={data:[{id:42,name:'Мираж'}]};
 else if(u.pathname==='/artist/42/albums')d=u.searchParams.has('index')?{data:[{id:2}]}:{data:[{id:1}],next:'https://api.deezer.com/artist/42/albums?index=1'};
 else if(u.pathname==='/album/1/tracks')d=u.searchParams.has('index')?{data:Array.from({length:20},(_,i)=>track(i+20))}:{data:Array.from({length:20},(_,i)=>track(i)),next:'https://api.deezer.com/album/1/tracks?index=20'};
 else if(u.pathname==='/album/2/tracks')d={data:[track(40),{...track(41),artist:{id:99,name:'Other'}}]};
 else throw Error(u.href);return {bytes:Buffer.from(JSON.stringify(d))};};
 const track=i=>({id:i,title:'Song '+i,artist:{id:42,name:'Мираж'},duration:200});
 const result=await scanArtistCatalog('Мираж',undefined,read);assert.equal(result.tracks.length,41);assert.equal(result.truncated,false);assert(seen.some(x=>x.includes('index=20')));
});
test('name import supplements a 20-result search with the complete album catalog',async()=>{
 const {scanSources}=await import('./providers.mjs');
 const read=async raw=>{const u=new URL(raw);let d;if(u.hostname==='spotsaver.net')d={type:'search',items:Array.from({length:20},(_,i)=>({id:i,title:'Song '+i,artist:'Мираж'}))};else if(u.hostname!=='api.deezer.com')throw Error('Source unavailable');else if(u.pathname==='/search/artist')d={data:[{id:42,name:'Мираж'}]};else if(u.pathname==='/artist/42/albums')d={data:[{id:1}]};else if(u.pathname==='/album/1/tracks')d={data:Array.from({length:45},(_,i)=>({id:i,title:'Song '+i,artist:{id:42,name:'Мираж'},duration:200}))};else throw Error('Unexpected URL');return {bytes:Buffer.from(JSON.stringify(d))}};
 const result=await scanSources('https://tunemir.com/','Мираж',undefined,read);assert.equal(result.tracks.length,45);assert.equal(result.truncated,false);assert(result.tracks.some(t=>t.sourceKey==='catalog:44'));
});
test('untrusted pagination and failed albums are never reported as a complete catalog',async()=>{
 const read=async raw=>{const u=new URL(raw);let d;if(u.pathname==='/search/artist')d={data:[{id:42,name:'Мираж'}]};else if(u.pathname==='/artist/42/albums')d={data:[{id:1},{id:2}]};else if(u.pathname==='/album/1/tracks')d={data:[{id:1,title:'Song',artist:{id:42,name:'Мираж'}}]};else if(u.pathname==='/album/2/tracks')d={data:[],next:'http://127.0.0.1/private'};else throw Error('External pagination reached transport');return {bytes:Buffer.from(JSON.stringify(d))}};
 const result=await scanArtistCatalog('Мираж',undefined,read);assert.equal(result.tracks.length,1);assert.equal(result.truncated,true);
});
