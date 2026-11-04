async function avatarFor(env,id,origin){const object=await env.BUCKET.head('avatars/'+id);return object?origin+'/api/avatar/'+id+'?v='+encodeURIComponent(object.httpEtag||object.uploaded?.toISOString()||'1'):null}
async function experienceRoute(r,env){
 const url=new URL(r.url),p=url.pathname;
 const avatar=p.match(/^\/api\/avatar\/([a-f0-9-]{36})$/i);
 if(avatar&&r.method==='GET'){
  const object=await env.BUCKET.get('avatars/'+avatar[1]);if(!object)return json(r,{error:'Аватарка не найдена'},404);
  return new Response(object.body,{headers:{...cors(r),'content-type':object.httpMetadata?.contentType||'image/jpeg','cache-control':'public,max-age=3600','x-content-type-options':'nosniff'}});
 }
 if(p==='/api/community/avatar'&&r.method==='POST'){
  const u=await account(r,env);if(!u)return json(r,{error:'Войди в аккаунт'},401);
  if(Number(r.headers.get('content-length'))>256000)return json(r,{error:'Аватарка слишком большая'},413);
  const bytes=new Uint8Array(await r.arrayBuffer());if(bytes.length>256000||bytes.length<20)return json(r,{error:'Нужен JPEG или PNG до 250 КБ'},400);
  const png=bytes[0]===137&&bytes[1]===80&&bytes[2]===78&&bytes[3]===71&&bytes[4]===13&&bytes[5]===10&&bytes[6]===26&&bytes[7]===10;
  const jpeg=bytes[0]===255&&bytes[1]===216&&bytes[2]===255;
  if(!png&&!jpeg)return json(r,{error:'Нужен JPEG или PNG'},415);
  await env.BUCKET.put('avatars/'+u.id,bytes,{httpMetadata:{contentType:png?'image/png':'image/jpeg'}});
  return json(r,{avatar:url.origin+'/api/avatar/'+u.id+'?v='+Date.now()});
 }
 if(p==='/api/lyrics'&&r.method==='GET'){
  const title=String(url.searchParams.get('title')||'').trim().slice(0,120),artist=String(url.searchParams.get('artist')||'').trim().slice(0,80),duration=Number(url.searchParams.get('duration'));
  if(!title||!artist)return json(r,{error:'Нужны название и исполнитель'},400);
  const params=new URLSearchParams({track_name:title,artist_name:artist});if(duration>0&&duration<=3600)params.set('duration',Math.round(duration));
  const key='lyrics/'+hex(await crypto.subtle.digest('SHA-256',enc.encode(params.toString())));
  const cached=await env.BUCKET.get(key);if(cached){const d=JSON.parse(await cached.text());if(d.until>Date.now())return json(r,d.result)}
  const response=await fetch('https://lrclib.net/api/get?'+params,{headers:{'User-Agent':'PulseMusic/1.0 (https://chapaev12241.github.io/pulsemusic/)'},signal:AbortSignal.timeout(8000)});
  if(!response.ok&&response.status!==404)return json(r,{error:'Источник текста временно недоступен'},502);
  const data=response.status===404?{}:await response.json();
  const result={found:!!(data.syncedLyrics||data.plainLyrics),instrumental:!!data.instrumental,syncedLyrics:String(data.syncedLyrics||'').slice(0,100000),plainLyrics:String(data.plainLyrics||'').slice(0,100000),source:'LRCLIB',sourceUrl:data.id?'https://lrclib.net/api/get/'+Number(data.id):'https://lrclib.net/'};
  await env.BUCKET.put(key,JSON.stringify({until:Date.now()+(result.found?30*86400000:3600000),result}));return json(r,result);
 }
 return null;
}
