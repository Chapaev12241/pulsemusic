import assert from 'node:assert/strict';import {DatabaseSync} from 'node:sqlite';import {readFileSync} from 'node:fs';
const {default:worker}=await import('data:text/javascript;base64,'+readFileSync('dist/server/index.js').toString('base64'));
const sqlite=new DatabaseSync(':memory:');sqlite.exec(readFileSync('drizzle/0000_pulse.sql','utf8').replaceAll('--> statement-breakpoint',''));
const DB={
  prepare(sql){
    return {bind(...args){
      return {
        async first(){return sqlite.prepare(sql).get(...args)||null},
        async run(){const r=sqlite.prepare(sql).run(...args);return {meta:{changes:Number(r.changes)}}}
      };
    }};
  }
};
const objects=new Map();function object(key,v){return{key,size:v.bytes.byteLength,customMetadata:v.customMetadata,httpEtag:'"test"',writeHttpMetadata(h){h.set('content-type',v.httpMetadata.contentType)}}}
const BUCKET={async head(k){return objects.has(k)?object(k,objects.get(k)):null},async put(k,bytes,opts){objects.set(k,{bytes,...opts})},async list({prefix}){return{objects:[...objects].filter(([k])=>k.startsWith(prefix)).map(([k,v])=>object(k,v)),truncated:false}},async get(k,opts){const v=objects.get(k);if(!v)return null;return{...object(k,v),body:opts?.range?v.bytes.slice(opts.range.offset,opts.range.offset+opts.range.length):v.bytes}}};
async function call(path,{token,method='GET',body,headers={}}={}){const h=new Headers(headers);h.set('origin','https://chapaev12241.github.io');if(token)h.set('authorization','Bearer '+token);if(body&&typeof body==='object'&&!(body instanceof ArrayBuffer)){h.set('content-type','application/json');body=JSON.stringify(body)}return worker.fetch(new Request('https://test.local'+path,{method,headers:h,body}),{DB,BUCKET})}
const password='QA-'+crypto.randomUUID();const register=await call('/api/auth/register',{method:'POST',body:{email:'one@example.invalid',password,name:'Тест'}});assert.equal(register.status,201);const one=await register.json();assert(!('password_hash'in one.user));
const login=await call('/api/auth/login',{method:'POST',body:{email:'one@example.invalid',password}});assert.equal(login.status,200);const secondSession=await login.json();assert.notEqual(one.token,secondSession.token);
assert.equal((await call('/api/auth/login',{method:'POST',body:{email:'one@example.invalid',password:'bad-password'}})).status,401);
const r2=await call('/api/auth/register',{method:'POST',body:{email:'two@example.invalid',password,name:'Другой'}}),two=await r2.json();assert.equal(r2.status,201);
const wav=Buffer.alloc(16044);wav.write('RIFF');wav.writeUInt32LE(wav.length-8,4);wav.write('WAVEfmt ',8);wav.writeUInt32LE(16,16);wav.writeUInt16LE(1,20);wav.writeUInt16LE(1,22);wav.writeUInt32LE(8000,24);wav.writeUInt32LE(16000,28);wav.writeUInt16LE(2,32);wav.writeUInt16LE(16,34);wav.write('data',36);wav.writeUInt32LE(16000,40);
const bytes=wav.buffer.slice(wav.byteOffset,wav.byteOffset+wav.byteLength),id=Buffer.from(await crypto.subtle.digest('SHA-256',bytes)).toString('hex');
assert.equal((await call('/api/music/'+id,{method:'POST',body:bytes,headers:{'x-file-name':encodeURIComponent('Тест - Волна.wav')}})).status,401);
assert.equal((await call('/api/music/'+id,{token:one.token,method:'POST',body:bytes,headers:{'x-file-name':encodeURIComponent('Тест - Волна.wav')}})).status,201);
const duplicate=await(await call('/api/music/'+id,{token:one.token,method:'POST',body:bytes,headers:{'x-file-name':encodeURIComponent('Тест - Волна.wav')}})).json();assert.equal(duplicate.duplicate,true);
const library=await(await call('/api/music',{token:secondSession.token})).json();assert.equal(library.tracks[0].title,'Волна');assert.equal((await(await call('/api/music',{token:two.token})).json()).tracks.length,0);
const signed=new URL(library.tracks[0].audio);const range=await call(signed.pathname+signed.search,{headers:{range:'bytes=100-199'}});assert.equal(range.status,206);assert.equal((await range.arrayBuffer()).byteLength,100);assert.equal(range.headers.get('content-range'),'bytes 100-199/16044');
signed.searchParams.set('u',two.user.id);assert.equal((await call(signed.pathname+signed.search)).status,403);
await Promise.all([{type:'playlist',id:'p1',name:'Мой плейлист'},{type:'like',id,value:true},{type:'history',id}].map(op=>call('/api/state',{token:one.token,method:'POST',body:{op}})));
await call('/api/state',{token:secondSession.token,method:'POST',body:{op:{type:'add',id,playlist:'p1'}}});const state=await(await call('/api/state',{token:secondSession.token})).json();assert.equal(state.playlists[0].tracks[0],id);assert.equal(state.liked[0],id);assert.equal(state.history[0].id,id);assert.equal((await(await call('/api/state',{token:two.token})).json()).playlists.length,0);
await call('/api/auth/logout',{token:one.token,method:'POST'});assert.equal((await call('/api/music',{token:one.token})).status,401);
console.log('PASS: registration/login, two sessions, account isolation, cloud upload, duplicate detection, signed media, byte ranges, concurrent playlist/history/likes and logout');
