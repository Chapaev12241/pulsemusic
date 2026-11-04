// Secrets arrive through hidden stdin; never put bot tokens in files or arguments.
import {createInterface} from 'node:readline';
if(process.stdin.isTTY)process.stdin.setRawMode(true);process.stdin.resume();console.log('Ready for Telegram configuration JSON on hidden stdin.');const rl=createInterface({input:process.stdin,terminal:false});const line=await new Promise(resolve=>rl.once('line',resolve));rl.close();process.stdin.pause();const config=JSON.parse(line);
if(!/^\d+:[\w-]+$/.test(config.token||'')||!/^[\w-]{20,256}$/.test(config.webhookSecret||''))throw Error('Invalid bot configuration');
async function call(method,body){const r=await fetch('https://api.telegram.org/bot'+config.token+'/'+method,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(20000)});const d=await r.json();if(!r.ok||!d.ok)throw Error(method+': '+String(d.description||r.status).replaceAll(config.token,'[redacted]'));return d.result}
const me=await call('getMe',{});if(config.username&&me.username?.toLowerCase()!==config.username.toLowerCase())throw Error('Unexpected bot username');
const app='https://chapaev12241.github.io/pulsemusic/telegram.html';
await call('setMyCommands',{commands:[{command:'start',description:'Открыть Pulse'},{command:'music',description:'Моя музыка'},{command:'settings',description:'Настройки'},{command:'help',description:'Помощь'}]});
await call('setMyDescription',{description:'Музыка, мой вайб и твои плейлисты. Открывай Pulse прямо в Telegram.'});
await call('setMyShortDescription',{short_description:'Pulse · твоя музыка'});
await call('setChatMenuButton',{menu_button:{type:'web_app',text:'Открыть Pulse',web_app:{url:app}}});
await call('setWebhook',{url:'https://pulse-vibe-music.desyatnichenkoiosyf2.chatgpt.site/api/telegram/webhook',secret_token:config.webhookSecret,allowed_updates:['message']});
const webhook=await call('getWebhookInfo',{});console.log(JSON.stringify({username:me.username,url:'https://t.me/'+me.username,app,webhook:webhook.url,pending:webhook.pending_update_count}));
