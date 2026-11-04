import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';import {DatabaseSync} from 'node:sqlite';import {createHmac} from 'node:crypto';
const {default:worker}=await import('data:text/javascript;base64,'+readFileSync('dist/server/index.js').toString('base64')),db=new DatabaseSync(':memory:');
for(const name of ['0000_pulse','0001_community','0002_artwork','0003_admin','0004_telegram'])db.exec(readFileSync('drizzle/'+name+'.sql','utf8').replaceAll('--> statement-breakpoint',''));
const DB={prepare(sql){const statement=db.prepare(sql),bound=args=>({async first(){return statement.get(...args)||null},async all(){return{results:statement.all(...args)}},async run(){return{meta:{changes:Number(statement.run(...args).changes)}}}});return{...bound([]),bind(...args){return bound(args)}}}};
const env={DB,TELEGRAM_BOT_TOKEN:'12345:test-only-secret',TELEGRAM_WEBHOOK_SECRET:'test-webhook-secret'},calls=[];const originalFetch=globalThis.fetch;let fail=false;
globalThis.fetch=async(url,options)=>{assert.equal(url,'https://api.telegram.org/bot'+env.TELEGRAM_BOT_TOKEN+'/sendMessage');calls.push(JSON.parse(options.body));return Response.json({ok:!fail},{status:fail?503:200})};
const request=(path,body,token,headers={})=>worker.fetch(new Request('https://pulse.test'+path,{method:body?'POST':'GET',headers:{'content-type':'application/json',...(token?{authorization:'Bearer '+token}:{}),...headers},body:body?JSON.stringify(body):undefined}),env);
function init(id,date=Math.floor(Date.now()/1000)){const p=new URLSearchParams({auth_date:String(date),query_id:'test-query',user:JSON.stringify({id,first_name:'Test'})}),key=createHmac('sha256','WebAppData').update(env.TELEGRAM_BOT_TOKEN).digest(),text=[...p].sort(([a],[b])=>a.localeCompare(b)).map(([k,v])=>k+'='+v).join('\n');p.set('hash',createHmac('sha256',key).update(text).digest('hex'));return p.toString()}
try{
 const one=await(await request('/api/auth/register',{email:'tg-one@example.invalid',password:'Test-password-123',name:'One'})).json(),two=await(await request('/api/auth/register',{email:'tg-two@example.invalid',password:'Test-password-456',name:'Two'})).json();assert(one.token&&two.token);
 assert.equal((await request('/api/telegram/login',{initData:init(1001)})).status,404);
 assert.equal((await request('/api/telegram/link',{initData:init(1001)},one.token)).status,200);
 const login=await(await request('/api/telegram/login',{initData:init(1001)})).json();assert.equal(login.user.id,one.user.id);assert.notEqual(login.token,one.token);
 assert.equal((await request('/api/telegram/link',{initData:init(1001)},two.token)).status,409);
 assert.equal((await request('/api/telegram/link',{initData:init(1002)},one.token)).status,409);
 assert.equal((await request('/api/telegram/login',{initData:init(1001).replace('Test','Forged')})).status,401);
 assert.equal((await request('/api/telegram/login',{initData:init(1001,Math.floor(Date.now()/1000)-601)})).status,401);
 assert.equal((await request('/api/telegram/login',{initData:init(1001)+'&auth_date=1'})).status,401);
 db.prepare('UPDATE pulse_accounts SET banned=1 WHERE id=?').run(one.user.id);assert.equal((await request('/api/telegram/login',{initData:init(1001)})).status,403);
 const update={update_id:1,message:{chat:{id:1001,type:'private'},text:'/start'}};
 assert.equal((await request('/api/telegram/webhook',update)).status,403);assert.equal(calls.length,0);
 const headers={'x-telegram-bot-api-secret-token':env.TELEGRAM_WEBHOOK_SECRET};assert.equal((await request('/api/telegram/webhook',update,null,headers)).status,200);assert.equal(calls.length,1);assert.match(calls[0].reply_markup.inline_keyboard[0][0].web_app.url,/\/pulsemusic\/telegram.html$/);
 await request('/api/telegram/webhook',update,null,headers);assert.equal(calls.length,1);
 fail=true;update.update_id=2;assert.equal((await request('/api/telegram/webhook',update,null,headers)).status,503);fail=false;assert.equal((await request('/api/telegram/webhook',update,null,headers)).status,200);
 assert.equal(db.prepare('SELECT COUNT(*) n FROM pulse_accounts').get().n,2);
 console.log('PASS: signed Telegram login, expired/forged data, link ownership, bans, webhook secret, duplicate updates and retry');
}finally{globalThis.fetch=originalFetch}
