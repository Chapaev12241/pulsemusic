import assert from 'node:assert/strict';import {DatabaseSync} from 'node:sqlite';import {readFileSync} from 'node:fs';
const {default:worker}=await import('data:text/javascript;base64,'+readFileSync('dist/server/index.js').toString('base64'));
const sqlite=new DatabaseSync(':memory:');sqlite.exec(readFileSync('drizzle/0000_pulse.sql','utf8').replaceAll('--> statement-breakpoint',''));sqlite.exec(readFileSync('drizzle/0001_community.sql','utf8').replaceAll('--> statement-breakpoint',''));
sqlite.exec(readFileSync('drizzle/0002_artwork.sql','utf8'));
sqlite.exec(readFileSync('drizzle/0003_admin.sql','utf8').replaceAll('--> statement-breakpoint',''));
const DB={async batch(statements){const results=[];for(const statement of statements)results.push(await statement.run());return results},
  prepare(sql){
    return {async all(){return {results:sqlite.prepare(sql).all()}},bind(...args){
      return {
        async first(){return sqlite.prepare(sql).get(...args)||null},async all(){return {results:sqlite.prepare(sql).all(...args)}},
        async run(){const r=sqlite.prepare(sql).run(...args);return {meta:{changes:Number(r.changes)}}}
      };
    }};
  }
};
const objects=new Map();function object(key,v){return{key,size:v.bytes.byteLength,customMetadata:v.customMetadata,httpEtag:'"test"',writeHttpMetadata(h){h.set('content-type',v.httpMetadata.contentType)}}}
const BUCKET={async head(k){return objects.has(k)?object(k,objects.get(k)):null},async put(k,bytes,opts={}){if(typeof bytes==='string')bytes=new TextEncoder().encode(bytes).buffer;objects.set(k,{bytes,...opts,httpMetadata:opts.httpMetadata||{contentType:'application/json'}})},async list({prefix}){return{objects:[...objects].filter(([k])=>k.startsWith(prefix)).map(([k,v])=>object(k,v)),truncated:false}},async get(k,opts){const v=objects.get(k);if(!v)return null;return{...object(k,v),async text(){return new TextDecoder().decode(v.bytes)},body:opts?.range?v.bytes.slice(opts.range.offset,opts.range.offset+opts.range.length):v.bytes}}};
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
assert.equal((await call('/api/music/'+id+'/meta',{token:two.token,method:'POST',body:{title:'Чужой',artist:'Другой',genres:['jazz']}})).status,404);
const updated=await call('/api/music/'+id+'/meta',{token:one.token,method:'POST',body:{title:'Волна 2',artist:'Артист',genres:['trap']}});assert.equal(updated.status,200);
const profile=await call('/api/artists/resolve',{token:one.token,method:'POST',body:{artist:'Артист',genres:['trap']}});assert.equal(profile.status,200);const edited=await(await call('/api/music',{token:one.token})).json();assert.equal(edited.tracks[0].title,'Волна 2');assert.equal(edited.tracks[0].genres[0],'trap');assert.equal(edited.tracks[0].genreSource,'manual');
const realFetch=globalThis.fetch;
try{globalThis.fetch=async url=>String(url).includes('musicbrainz.org')?new Response('{}',{status:503}):new Response(JSON.stringify({results:[{artistName:'FallbackArtist',artistId:123,primaryGenreName:'Jazz'}]}),{headers:{'content-type':'application/json'}});const fallback=await call('/api/artists/resolve',{token:one.token,method:'POST',body:{artist:'FallbackArtist'}});assert.equal(fallback.status,200);const resolved=await fallback.json();assert.equal(resolved.source,'apple');assert.equal(resolved.genres[0],'jazz');assert.equal(resolved.artistId,'apple:123')}finally{globalThis.fetch=realFetch}
// Simulate an upload made before the shared catalog existed.
sqlite.prepare('DELETE FROM pulse_catalog WHERE id=?').run(id);
const catalogResponse=await(await call('/api/catalog')).json();assert(catalogResponse.tracks.some(t=>t.id===id));assert.equal(catalogResponse.tracks.find(t=>t.id===id).title,'Волна 2');assert.equal(catalogResponse.indexing,false);assert.equal((await(await call('/api/catalog',{token:two.token})).json()).tracks.find(t=>t.id===id).artist,'Артист');
await call('/api/catalog/'+id+'/visibility',{token:one.token,method:'POST',body:{public:false}});objects.delete('system/catalog-backfill-v1');assert(!(await(await call('/api/catalog')).json()).tracks.some(t=>t.id===id));await call('/api/catalog/'+id+'/visibility',{token:one.token,method:'POST',body:{public:true}});assert.equal((await call('/api/public-stream/'+id,{headers:{range:'bytes=0-99'}})).status,206);
assert.equal((await call('/api/community/messages',{token:one.token,method:'POST',body:{to:two.user.id,body:'test'}})).status,403);
await call('/api/community/request',{token:one.token,method:'POST',body:{id:two.user.id}});const incoming=await(await call('/api/community/me',{token:two.token})).json();assert.equal(incoming.incoming[0].id,one.user.id);await call('/api/community/respond',{token:two.token,method:'POST',body:{id:one.user.id,accept:true}});
assert.equal((await call('/api/community/messages',{token:one.token,method:'POST',body:{to:two.user.id,body:'Привет'}})).status,200);const thread=await(await call('/api/community/messages?with='+one.user.id,{token:two.token})).json();assert.equal(thread.messages[0].body,'Привет');
const strangerResponse=await call('/api/auth/register',{method:'POST',body:{email:'stranger@example.invalid',password,name:'Третий'}});const stranger=await strangerResponse.json();assert.equal(strangerResponse.status,201);assert.equal((await call('/api/community/messages?with='+one.user.id,{token:stranger.token})).status,403);assert.equal((await call('/api/community/respond',{token:stranger.token,method:'POST',body:{id:one.user.id,accept:true}})).status,404);
await call('/api/community/profile',{token:one.token,method:'POST',body:{name:'Новое имя',bio:'Люблю музыку',color:'#123456',emoji:'♫'}});const visible=await(await call('/api/community/profile/'+one.user.id,{token:two.token})).json();assert.equal(visible.profile.name,'Новое имя');assert.equal(visible.profile.email,undefined);
assert.equal((await call('/api/community/me')).status,401);
assert.equal((await call('/api/community/avatar',{method:'POST',body:bytes})).status,401);
assert.equal((await call('/api/community/avatar',{token:one.token,method:'POST',body:bytes})).status,415);
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII=','base64');
assert.equal((await call('/api/community/avatar',{token:one.token,method:'POST',body:png.buffer.slice(png.byteOffset,png.byteOffset+png.byteLength)})).status,200);
const avatarProfile=await(await call('/api/community/profile/'+one.user.id,{token:two.token})).json();assert(avatarProfile.profile.avatar.includes('/api/avatar/'+one.user.id));assert.equal((await call('/api/avatar/'+one.user.id)).status,200);

assert.equal((await call('/api/track-cover/'+id,{token:two.token,method:'POST',body:bytes})).status,404);
assert.equal((await call('/api/track-cover/'+id+'/match',{token:one.token,method:'POST',body:{url:'https://example.invalid/cover.jpg'}})).status,400);
const jpeg=new Uint8Array(24);jpeg.set([255,216,255]);
assert.equal((await call('/api/track-cover/'+id,{token:one.token,method:'POST',body:jpeg.buffer})).status,200);
assert.equal((await call('/api/track-cover/'+id)).status,200);
const sharedCover=await(await call('/api/artwork?artist='+encodeURIComponent('Артист')+'&title='+encodeURIComponent('Волна 2'),{token:two.token})).json();assert(sharedCover.url.includes('/api/track-cover/'+id));
const fetchBeforeLyrics=globalThis.fetch;
try{globalThis.fetch=async()=>new Response(JSON.stringify({id:123,syncedLyrics:'[00:01.00]Synthetic test line',plainLyrics:'Synthetic test line'}),{headers:{'content-type':'application/json'}});const lyrics=await(await call('/api/lyrics?title=Test&artist=Test&duration=60')).json();assert.equal(lyrics.found,true);assert(lyrics.syncedLyrics.startsWith('[00:01.00]'));globalThis.fetch=async()=>{throw Error('Should use cache')};assert.equal((await call('/api/lyrics?title=Test&artist=Test&duration=60')).status,200)}finally{globalThis.fetch=fetchBeforeLyrics}
assert.equal((await call('/api/lyrics?title=Test')).status,400);
for(let i=0;i<105;i++)await DB.prepare('INSERT INTO pulse_messages(sender,recipient,body,created_at) VALUES(?,?,?,?)').bind(one.user.id,two.user.id,'Page '+i,new Date().toISOString()).run();
const latest=await(await call('/api/community/messages?with='+two.user.id,{token:one.token})).json();assert.equal(latest.messages.length,100);assert.equal(latest.hasMore,true);const older=await(await call('/api/community/messages?with='+two.user.id+'&before='+latest.messages[0].id,{token:one.token})).json();assert(older.messages.length>0);assert(older.messages.at(-1).id<latest.messages[0].id);


assert.equal((await call('/api/admin/users')).status,401);
assert.equal((await call('/api/admin/users',{token:two.token})).status,403);
assert.equal((await call('/api/admin/tracks/'+id+'/remove',{token:two.token,method:'POST',body:{}})).status,403);
const ownerRequest=new Request('https://test.local/api/auth/me',{headers:{authorization:'Bearer '+one.token}});
const ownerResponse=await worker.fetch(ownerRequest,{DB,BUCKET,PULSE_ADMIN_EMAIL:'one@example.invalid',PULSE_ADMIN_CREATED_BEFORE:new Date(Date.now()+1000).toISOString()});assert.equal((await ownerResponse.json()).user.role,'admin');
assert.equal((await call('/api/admin/users',{token:one.token})).status,200);
assert.equal((await call('/api/admin/users/'+one.user.id+'/ban',{token:one.token,method:'POST',body:{banned:true}})).status,400);
assert.equal((await call('/api/admin/users/'+two.user.id+'/ban',{token:one.token,method:'POST',body:{banned:true}})).status,200);
assert.equal((await call('/api/state',{token:two.token})).status,401);
assert.equal((await call('/api/auth/login',{method:'POST',body:{email:'two@example.invalid',password}})).status,403);
assert.equal((await call('/api/admin/users/'+two.user.id+'/ban',{token:one.token,method:'POST',body:{banned:false}})).status,200);
assert.equal((await call('/api/auth/login',{method:'POST',body:{email:'two@example.invalid',password}})).status,200);
assert.equal((await call('/api/admin/tracks/'+id+'/remove',{token:one.token,method:'POST',body:{}})).status,200);
assert(!(await(await call('/api/catalog')).json()).tracks.some(t=>t.id===id));
assert(!(await(await call('/api/music',{token:one.token})).json()).tracks.some(t=>t.id===id));
assert.equal((await call('/api/public-stream/'+id)).status,404);
assert.equal((await call('/api/admin/tracks/'+id+'/restore',{token:one.token,method:'POST',body:{}})).status,200);
assert((await(await call('/api/catalog')).json()).tracks.some(t=>t.id===id));
assert((await(await call('/api/admin/audit',{token:one.token})).json()).events.length>=4);
const beforeFallback=globalThis.fetch;try{globalThis.fetch=async url=>String(url).startsWith('https://api.lyrics.ovh/')?new Response(JSON.stringify({lyrics:'Synthetic fallback text'}),{headers:{'content-type':'application/json'}}):new Response('{}',{status:404});const fallbackLyrics=await(await call('/api/lyrics?title=Fallback%20test&artist=Fallback%20artist&duration=45')).json();assert.equal(fallbackLyrics.source,'Lyrics.ovh');assert.equal(fallbackLyrics.syncedLyrics,'');assert.equal(fallbackLyrics.plainLyrics,'Synthetic fallback text')}finally{globalThis.fetch=beforeFallback}
await call('/api/auth/logout',{token:one.token,method:'POST'});assert.equal((await call('/api/music',{token:one.token})).status,401);
console.log('PASS: registration/login, two sessions, account isolation, cloud upload, duplicate detection, signed media, byte ranges, concurrent playlist/history/likes and logout; community profiles, friend acceptance, private messaging and public catalog isolation');
