// Pulse Connect: account-scoped presence and acknowledged, idempotent playback commands.
const DEVICE_TTL = 35000, DEVICE_COMMAND_TTL = 30000;
function deviceUUID(value) { const id=String(value||'').toLowerCase(); if(!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(id))throw Error('Неверный идентификатор устройства');return id }
function deviceNumber(value,min,max,fallback=0){const n=Number(value);return Number.isFinite(n)?Math.min(max,Math.max(min,n)):fallback}
function deviceState(value={}){
 const trackId=String(value.trackId||'');if(trackId&&!/^[a-f0-9]{64}$/.test(trackId))throw Error('Неверный трек');
 const duration=deviceNumber(value.duration,0,86400);
 return {trackId,position:deviceNumber(value.position,0,duration||86400),duration,paused:value.paused!==false,buffering:value.buffering===true,shuffle:value.shuffle===true,dj:value.dj!==false,volume:deviceNumber(value.volume,0,1,0.8)};
}
function deviceQueue(value){if(!Array.isArray(value)||value.length>2000||value.some(id=>typeof id!=='string'||!/^[a-f0-9]{64}$/.test(id)))throw Error('Неверная очередь');return [...new Set(value)]}
async function deviceBody(r){if(Number(r.headers.get('content-length'))>350000)throw Error('Слишком большой запрос');const reader=r.body?.getReader();if(!reader)return{};let text='',length=0;const decoder=new TextDecoder();for(;;){const {done,value}=await reader.read();if(done)break;length+=value.byteLength;if(length>350000){await reader.cancel();throw Error('Слишком большой запрос')}text+=decoder.decode(value,{stream:true})}text+=decoder.decode();return JSON.parse(text||'{}')}
async function deviceFind(env,uid,id){return env.DB.prepare('SELECT * FROM pulse_devices WHERE user_id=? AND id=?').bind(uid,id).first()}
async function deviceFocus(env,uid){return env.DB.prepare('SELECT * FROM pulse_device_focus WHERE user_id=?').bind(uid).first()}
function devicePublic(row,now){
 const state=deviceState(JSON.parse(row.state_json)),online=!!row.available&&row.seen_at>=now-DEVICE_TTL;
 if(online&&!state.paused&&!state.buffering)state.position=Math.min(state.duration||86400,state.position+Math.min(DEVICE_TTL/1000,Math.max(0,now-row.seen_at)/1000));
 return {id:row.id,name:row.name,platform:row.platform,online,ready:!!row.ready,lastSeen:row.seen_at,state};
}
async function deviceExpire(env,uid,now){
 await env.DB.prepare("UPDATE pulse_device_commands SET status='error',error='Устройство не ответило вовремя',completed_at=? WHERE user_id=? AND status='pending' AND created_at<?").bind(now,uid,now-DEVICE_COMMAND_TTL).run();
 await env.DB.prepare("UPDATE pulse_device_focus SET pending_id=NULL,revision=revision+1 WHERE user_id=? AND pending_id IN (SELECT id FROM pulse_device_commands WHERE user_id=? AND status<>'pending')").bind(uid,uid).run();
 await env.DB.prepare('DELETE FROM pulse_device_commands WHERE user_id=? AND created_at<?').bind(uid,now-86400000).run();
}
async function deviceResponse(r,env,uid,caller,watch,extra={}){
 const now=Date.now();await deviceExpire(env,uid,now);
 const rows=await env.DB.prepare('SELECT * FROM pulse_devices WHERE user_id=? ORDER BY seen_at DESC LIMIT 32').bind(uid).all();
 const devices=rows.results.map(row=>devicePublic(row,now)),focus=await deviceFocus(env,uid),active=devices.find(d=>d.id===focus?.device_id);
 const command=await env.DB.prepare("SELECT * FROM pulse_device_commands WHERE user_id=? AND target_id=? AND status='pending' AND created_at>=? AND ((type='transfer' AND id=?) OR (type='control' AND target_id=?)) ORDER BY seq LIMIT 1").bind(uid,caller,now-DEVICE_COMMAND_TTL,focus?.pending_id||'',focus?.device_id||'').first();
 const watched=watch?await env.DB.prepare('SELECT id,status,error,source_id,target_id FROM pulse_device_commands WHERE user_id=? AND id=?').bind(uid,deviceUUID(watch)).first():null;
 return json(r,{deviceId:caller,devices,focus:{deviceId:focus?.device_id||null,revision:focus?.revision||0,pendingId:focus?.pending_id||null,name:active?.name||'',online:active?.online||false,state:active?.state||null},command:command?{id:command.id,type:command.type,payload:JSON.parse(command.payload_json),createdAt:command.created_at}:null,watched:watched?{id:watched.id,status:watched.status,error:watched.error,sourceId:watched.source_id,targetId:watched.target_id}:null,serverTime:now,...extra});
}
async function deviceHeartbeat(env,uid,body,now){
 const id=deviceUUID(body.deviceId),old=await deviceFind(env,uid,id);
 if(!old){const count=await env.DB.prepare('SELECT COUNT(*) AS n FROM pulse_devices WHERE user_id=?').bind(uid).first();if(count.n>=32){await env.DB.prepare('DELETE FROM pulse_devices WHERE user_id=? AND seen_at<?').bind(uid,now-86400000).run();const remaining=await env.DB.prepare('SELECT COUNT(*) AS n FROM pulse_devices WHERE user_id=?').bind(uid).first();if(remaining.n>=32)throw Error('В аккаунте уже 32 устройства')}}
 const name=String(body.name||'Pulse').replace(/[\u0000-\u001f]/g,'').trim().slice(0,80)||'Pulse';const platform=['ios','macos','windows','web'].includes(body.platform)?body.platform:'web';
 const state=deviceState(body.state),queue=body.queue===undefined?null:deviceQueue(body.queue),original=body.originalQueue===undefined?queue:deviceQueue(body.originalQueue);
 await env.DB.prepare('INSERT INTO pulse_devices(user_id,id,name,platform,available,ready,state_json,queue_json,original_queue_json,seen_at) VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(user_id,id) DO UPDATE SET name=excluded.name,platform=excluded.platform,available=excluded.available,ready=excluded.ready,state_json=excluded.state_json,queue_json=CASE WHEN ? THEN excluded.queue_json ELSE pulse_devices.queue_json END,original_queue_json=CASE WHEN ? THEN excluded.original_queue_json ELSE pulse_devices.original_queue_json END,seen_at=excluded.seen_at').bind(uid,id,name,platform,body.available!==false?1:0,body.ready===true?1:0,JSON.stringify(state),JSON.stringify(queue||[]),JSON.stringify(original||[]),now,queue!==null?1:0,original!==null?1:0).run();
 if(state.trackId&&!state.paused)await env.DB.prepare('INSERT INTO pulse_device_focus(user_id,device_id,updated_at) VALUES(?,?,?) ON CONFLICT(user_id) DO NOTHING').bind(uid,id,now).run();return id;
}
async function deviceCanPlay(env,uid,id){return !!await env.DB.prepare('SELECT id FROM pulse_catalog WHERE id=? AND deleted_at IS NULL AND (is_public=1 OR owner_id=?)').bind(id,uid).first()}
async function deviceEnqueue(env,uid,caller,target,type,payload,requestId,now){
 const id=deviceUUID(requestId);await env.DB.prepare("INSERT INTO pulse_device_commands(id,user_id,source_id,target_id,type,payload_json,created_at) VALUES(?,?,?,?,?,?,?) ON CONFLICT(id) DO NOTHING").bind(id,uid,caller,target,type,JSON.stringify(payload),now).run();
 const command=await env.DB.prepare('SELECT * FROM pulse_device_commands WHERE id=? AND user_id=?').bind(id,uid).first();if(!command||command.target_id!==target||command.type!==type)throw Error('Идентификатор запроса уже использован');
 if(command.status==='pending'){
  await env.DB.prepare('INSERT INTO pulse_device_focus(user_id,device_id,last_seq,pending_id,revision,updated_at) VALUES(?,?,?,?,1,?) ON CONFLICT(user_id) DO UPDATE SET last_seq=excluded.last_seq,pending_id=excluded.pending_id,revision=pulse_device_focus.revision+1,updated_at=excluded.updated_at WHERE pulse_device_focus.last_seq<excluded.last_seq').bind(uid,caller,command.seq,type==='transfer'?id:null,now).run();
  const focus=await deviceFocus(env,uid);
  await env.DB.prepare("UPDATE pulse_device_commands SET status='obsolete',completed_at=? WHERE user_id=? AND type='transfer' AND status='pending' AND seq<? AND id<>?").bind(now,uid,focus.last_seq,focus.pending_id||'').run();
  if(type==='transfer'&&focus.pending_id!==id)await env.DB.prepare("UPDATE pulse_device_commands SET status='obsolete',completed_at=? WHERE id=? AND user_id=? AND status='pending'").bind(now,id,uid).run();
 }
 return id;
}
async function devicesRoute(r,env){
 const path=new URL(r.url).pathname;if(path!=='/api/devices')return null;
 const user=await account(r,env);if(!user)return json(r,{error:'Войди в аккаунт'},401);
 try{
  const now=Date.now();
  if(r.method==='GET'){const u=new URL(r.url);return await deviceResponse(r,env,user.id,deviceUUID(u.searchParams.get('deviceId')),u.searchParams.get('watch'))}
  if(r.method!=='POST')return json(r,{error:'Метод не поддерживается'},405);
  const body=await deviceBody(r),action=body.action||'heartbeat',caller=deviceUUID(body.deviceId);
  if(action==='heartbeat'){await deviceHeartbeat(env,user.id,body,now);return await deviceResponse(r,env,user.id,caller,body.watch)}
  const self=await deviceFind(env,user.id,caller);if(!self)return json(r,{error:'Сначала зарегистрируй устройство'},409);
  if(action==='leave'){await env.DB.prepare('UPDATE pulse_devices SET available=0,ready=0,seen_at=? WHERE user_id=? AND id=?').bind(now,user.id,caller).run();return json(r,{ok:true})}
  if(action==='claim'){
   if(body.state)await env.DB.prepare('UPDATE pulse_devices SET state_json=?,seen_at=? WHERE user_id=? AND id=?').bind(JSON.stringify(deviceState(body.state)),now,user.id,caller).run();
   const seq=(await env.DB.prepare('SELECT COALESCE(MAX(seq),0) AS seq FROM pulse_device_commands WHERE user_id=?').bind(user.id).first()).seq;
   await env.DB.batch([env.DB.prepare('INSERT INTO pulse_device_focus(user_id,device_id,last_seq,pending_id,revision,updated_at) VALUES(?,?,?,NULL,1,?) ON CONFLICT(user_id) DO UPDATE SET device_id=excluded.device_id,last_seq=MAX(pulse_device_focus.last_seq,excluded.last_seq),pending_id=NULL,revision=pulse_device_focus.revision+1,updated_at=excluded.updated_at').bind(user.id,caller,seq,now),env.DB.prepare("UPDATE pulse_device_commands SET status='obsolete',completed_at=? WHERE user_id=? AND status='pending' AND seq<=?").bind(now,user.id,seq)]);
   return await deviceResponse(r,env,user.id,caller,body.watch);
  }
  if(action==='transfer'||action==='control'){
   await deviceExpire(env,user.id,now);const target=deviceUUID(body.targetId),row=await deviceFind(env,user.id,target);
   if(!row||!devicePublic(row,now).online)return json(r,{error:'Устройство сейчас не в сети'},409);
   if(!row.ready)return json(r,{error:'Открой плеер и разреши воспроизведение на выбранном устройстве'},409);
   const focus=await deviceFocus(env,user.id);let payload;
   if(action==='transfer'){
    const source=focus?.device_id?await deviceFind(env,user.id,focus.device_id):self;const from=source||self;
    const fresh=from.id===caller&&body.snapshot?deviceState(body.snapshot):devicePublic(from,now).state;
    if(!fresh.trackId||!await deviceCanPlay(env,user.id,fresh.trackId))return json(r,{error:'Сначала выбери доступный трек'},400);
    let queue=from.id===caller&&body.queue!==undefined?deviceQueue(body.queue):deviceQueue(JSON.parse(from.queue_json));if(!queue.includes(fresh.trackId))queue=[fresh.trackId,...queue].slice(0,2000);
    const original=from.id===caller&&body.originalQueue!==undefined?deviceQueue(body.originalQueue):deviceQueue(JSON.parse(from.original_queue_json));
    payload={state:fresh,queue,originalQueue:original.length?original:queue,sourceId:from.id};
   }else{
    if(focus?.device_id!==target)return json(r,{error:'Активное устройство изменилось. Обнови список.'},409);
    const op=String(body.command||'');if(!['resume','pause','next','previous','seek','shuffle','volume','dj'].includes(op))throw Error('Неизвестная команда');
    payload={command:op};if(op==='seek')payload.position=deviceNumber(body.position,0,86400);if(op==='volume')payload.value=deviceNumber(body.value,0,1);if(op==='shuffle'||op==='dj')payload.enabled=body.enabled===true;
   }
   const requestId=await deviceEnqueue(env,user.id,caller,target,action,payload,body.requestId,now);
   return await deviceResponse(r,env,user.id,caller,requestId,{requestId});
  }
  if(action==='ack'){
   await deviceExpire(env,user.id,now);
   const id=deviceUUID(body.commandId),command=await env.DB.prepare('SELECT * FROM pulse_device_commands WHERE id=? AND user_id=? AND target_id=?').bind(id,user.id,caller).first();
   if(!command)return json(r,{error:'Команда не найдена'},404);
   if(command.status==='pending'){
    let status=body.success===true?'applied':'error',error=body.success===true?'':String(body.error||'Не удалось включить трек на устройстве').slice(0,200);
    if(status==='applied'&&command.type==='transfer'){
     const updated=await env.DB.prepare('UPDATE pulse_device_focus SET device_id=?,pending_id=NULL,revision=revision+1,updated_at=? WHERE user_id=? AND pending_id=? AND last_seq=?').bind(caller,now,user.id,id,command.seq).run();
     if(!updated.meta.changes){const focus=await deviceFocus(env,user.id);if(!(focus?.device_id===caller&&focus?.last_seq===command.seq&&!focus?.pending_id))status='obsolete'}
    }
    if(status==='error')await env.DB.prepare('UPDATE pulse_device_focus SET pending_id=NULL,revision=revision+1 WHERE user_id=? AND pending_id=?').bind(user.id,id).run();
    if(command.type==='control'){const focus=await deviceFocus(env,user.id);if(focus?.device_id!==caller)status='obsolete'}
    await env.DB.prepare("UPDATE pulse_device_commands SET status=?,error=?,completed_at=? WHERE user_id=? AND id=? AND status='pending'").bind(status,error,now,user.id,id).run();
   }
   if(body.state)await env.DB.prepare('UPDATE pulse_devices SET state_json=?,seen_at=? WHERE user_id=? AND id=?').bind(JSON.stringify(deviceState(body.state)),now,user.id,caller).run();
   return await deviceResponse(r,env,user.id,caller,body.watch||id);
  }
  return json(r,{error:'Неизвестное действие'},400);
 }catch(e){return json(r,{error:e instanceof SyntaxError?'Неверный JSON':String(e.message||'Не удалось связать устройства')},400)}
}
