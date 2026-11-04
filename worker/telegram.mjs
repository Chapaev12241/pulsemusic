async function telegramHmac(key,value){const k=await crypto.subtle.importKey('raw',typeof key==='string'?new TextEncoder().encode(key):key,{name:'HMAC',hash:'SHA-256'},false,['sign']);return new Uint8Array(await crypto.subtle.sign('HMAC',k,new TextEncoder().encode(value)))}
async function telegramIdentity(raw,botToken,now=Date.now()){
 if(typeof raw!=='string'||raw.length>16384||!botToken)return null;const data=new URLSearchParams(raw),seen=new Set();for(const[key]of data){if(seen.has(key))return null;seen.add(key)}
 const hash=data.get('hash')||'',date=Number(data.get('auth_date'));if(!/^[a-f0-9]{64}$/.test(hash)||!Number.isSafeInteger(date)||date*1000>now+30000||now-date*1000>600000)return null;
 data.delete('hash');const check=[...data].sort(([a],[b])=>a<b?-1:a>b?1:0).map(([key,value])=>key+'='+value).join('\n'),secret=await telegramHmac('WebAppData',botToken),actual=[...await telegramHmac(secret,check)].map(b=>b.toString(16).padStart(2,'0')).join('');
 if(!equal(actual,hash))return null;let user;try{user=JSON.parse(data.get('user'))}catch{return null}if(!Number.isSafeInteger(user?.id)||user.id<=0||user.is_bot)return null;return{id:String(user.id),name:String(user.first_name||'').slice(0,80)};
}
function telegramAppURL(section='home'){const u=new URL('https://chapaev12241.github.io/pulsemusic/telegram.html');if(section!=='home')u.searchParams.set('view',section);return u.href}
async function telegramRoute(r,env){const url=new URL(r.url),p=url.pathname;if(!p.startsWith('/api/telegram/'))return null;
 if(p==='/api/telegram/status'&&r.method==='GET')return json(r,{configured:!!env.TELEGRAM_BOT_TOKEN,username:String(env.TELEGRAM_BOT_USERNAME||''),appUrl:telegramAppURL()});
 if(p==='/api/telegram/webhook'){
  if(r.method!=='POST')return json(r,{error:'Метод не поддерживается'},405);
  if(!env.TELEGRAM_WEBHOOK_SECRET||!equal(r.headers.get('x-telegram-bot-api-secret-token')||'',env.TELEGRAM_WEBHOOK_SECRET))return json(r,{error:'Нет доступа'},403);
  const body=await r.text();if(body.length>32768)return json(r,{error:'Слишком большой запрос'},413);let update;try{update=JSON.parse(body)}catch{return json(r,{error:'Неверный запрос'},400)}
  if(!Number.isSafeInteger(update.update_id)||update.update_id<0)return json(r,{error:'Неверное обновление'},400);
  const m=update.message;if(!m||m.chat?.type!=='private'||!Number.isSafeInteger(m.chat?.id)||typeof m.text!=='string')return json(r,{ok:true});
  const command=m.text.split(/\s/)[0].split('@')[0];if(!['/start','/music','/help','/settings'].includes(command))return json(r,{ok:true});
  if(!env.TELEGRAM_BOT_TOKEN)return json(r,{error:'Бот ещё не подключён'},503);
  const inserted=await env.DB.prepare('INSERT INTO pulse_telegram_updates(update_id,created_at) VALUES(?,?) ON CONFLICT(update_id) DO NOTHING').bind(update.update_id,new Date().toISOString()).run();if(!inserted.meta.changes)return json(r,{ok:true});
  const payload={chat_id:m.chat.id,text:command==='/help'?'Открой Pulse кнопкой ниже. Аккаунт, плейлисты и история — общие с веб-версией.':'Pulse · твоя музыка',reply_markup:{inline_keyboard:[[{text:'Открыть Pulse',web_app:{url:telegramAppURL(command==='/settings'?'settings':'home')}}]]}};
  try{const response=await fetch('https://api.telegram.org/bot'+env.TELEGRAM_BOT_TOKEN+'/sendMessage',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(payload),signal:AbortSignal.timeout(8000)});const data=await response.json();if(!response.ok||!data.ok)throw Error('Telegram unavailable')}catch{await env.DB.prepare('DELETE FROM pulse_telegram_updates WHERE update_id=?').bind(update.update_id).run();return json(r,{error:'Повтори запрос позже'},503)}
  if(update.update_id%100===0)await env.DB.prepare('DELETE FROM pulse_telegram_updates WHERE created_at<?').bind(new Date(Date.now()-7*864e5).toISOString()).run();return json(r,{ok:true});
 }
 if(!['/api/telegram/login','/api/telegram/link'].includes(p)||r.method!=='POST')return json(r,{error:'Не найдено'},404);
 if(!env.TELEGRAM_BOT_TOKEN)return json(r,{error:'Telegram ещё не подключён'},503);if(limited(r))return json(r,{error:'Подожди минуту и повтори'},429);
 let data;try{data=await r.json()}catch{return json(r,{error:'Неверный запрос'},400)}const identity=await telegramIdentity(data.initData,env.TELEGRAM_BOT_TOKEN);if(!identity)return json(r,{error:'Открой Pulse заново через бота Telegram'},401);
 const link=await env.DB.prepare('SELECT user_id FROM pulse_telegram_links WHERE telegram_id=?').bind(identity.id).first();
 if(p.endsWith('/link')){const u=await account(r,env);if(!u)return json(r,{error:'Сначала войди в аккаунт Pulse'},401);if(link&&link.user_id!==u.id)return json(r,{error:'Этот Telegram уже связан с другим аккаунтом Pulse'},409);const other=await env.DB.prepare('SELECT telegram_id FROM pulse_telegram_links WHERE user_id=?').bind(u.id).first();if(other&&other.telegram_id!==identity.id)return json(r,{error:'У аккаунта уже подключён другой Telegram'},409);try{await env.DB.prepare('INSERT INTO pulse_telegram_links(telegram_id,user_id,created_at) VALUES(?,?,?) ON CONFLICT(telegram_id) DO NOTHING').bind(identity.id,u.id,new Date().toISOString()).run()}catch{return json(r,{error:'Не удалось связать аккаунт. Повтори запрос'},409)}const saved=await env.DB.prepare('SELECT user_id FROM pulse_telegram_links WHERE telegram_id=?').bind(identity.id).first();if(saved?.user_id!==u.id)return json(r,{error:'Telegram уже связан с другим аккаунтом'},409);return json(r,{linked:true})}
 if(!link)return json(r,{error:'Войди в Pulse по email и свяжи Telegram в настройках'},404);const u=await env.DB.prepare('SELECT * FROM pulse_accounts WHERE id=? AND banned=0').bind(link.user_id).first();if(!u)return json(r,{error:'Аккаунт недоступен'},403);return json(r,await session(env,u));
}
