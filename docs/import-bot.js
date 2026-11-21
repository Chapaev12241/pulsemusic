'use strict';
const $=id=>document.getElementById(id),key='pulseImportAdminSession';let session=sessionStorage.getItem(key)||'',jobsSnapshot='';
function notice(s){$('notice').textContent=s}
async function request(path,body){const r=await fetch(path,{method:body?'POST':'GET',headers:{...(session?{authorization:'Bearer '+session}:{}),...(body?{'content-type':'application/json'}:{})},body:body?JSON.stringify(body):undefined});const d=await r.json();if(!r.ok){if(r.status===401){session='';sessionStorage.removeItem(key);$('loginCard').hidden=false;$('connectCard').hidden=true;$('jobsPanel').hidden=true}throw Error(d.error||'Сервис недоступен')}return d}
async function refresh(){
 if(!session)return;const currentSession=session,d=await request('/api/import-admin');if(currentSession!==session)return;
 $('loginCard').hidden=true;$('connectCard').hidden=false;$('jobsPanel').hidden=false;$('connectForm').hidden=d.configured;$('pairPanel').hidden=!d.configured;$('dispatchPanel').hidden=!d.configured;$('githubForm').hidden=d.autoStart&&!d.autoStartError;$('wakeButton').hidden=!d.autoStart;
 $('dispatchState').textContent=d.autoStartError||(d.autoStart?'Автозапуск подключён. Новое сообщение отправляет запрос в GitHub Actions; время старта зависит от очереди GitHub.':'Подключи GitHub, чтобы новые задания отправлялись в загрузчик сразу. Запуск по расписанию может задерживаться.');
 $('botTitle').textContent=d.configured?'@'+d.username:'Отдельный Telegram-бот';$('botDescription').textContent=d.configured?'Бот подключён к облачной очереди Pulse.':'Открой BotFather, отправь /newbot и создай нового бота. Скопируй его токен сюда.';
 $('pairState').textContent=d.paired?'Telegram привязан. Отправляй задания своему боту.':'Осталось привязать твой Telegram. Ссылка действует 30 минут.';$('pairButton').hidden=d.paired;if(d.paired)$('pairLink').hidden=true;
 const jobs=Array.isArray(d.jobs)?d.jobs:[],pending=jobs.some(j=>j.status==='queued');$('workerStatus').textContent=pending&&(!d.worker||Date.now()-d.worker.last_seen>600000)?'Задания сохранены. Загрузчик давно не выходил на связь — проверь GitHub Actions.':d.worker?'Загрузчик выходил на связь: '+new Date(d.worker.last_seen).toLocaleString('ru-RU'):'';
 const snapshot=JSON.stringify(jobs);if(snapshot===jobsSnapshot)return;jobsSnapshot=snapshot;$('jobs').replaceChildren();
 const names={queued:'В очереди',running:'Загружается',done:'Готово',partial:'Частично',error:'Ошибка',cancelled:'Отменено'},number=value=>Math.max(0,Math.floor(Number(value)||0));
 for(const j of jobs){
  const row=document.createElement('div');row.className='job';row.dataset.status=j.status;const info=document.createElement('div'),heading=document.createElement('div'),title=document.createElement('strong'),badge=document.createElement('span'),counts=document.createElement('div');heading.className='job-heading';title.textContent=j.artist||'Загрузка по ссылке';heading.append(title);
  if(j.sourceHost){const host=document.createElement('small');host.textContent=j.sourceHost;heading.append(host)}
  counts.className='job-counts';const metric=(label,value,kind='')=>{const span=document.createElement('span'),b=document.createElement('b');span.className=kind;span.append(document.createTextNode(label+' '));b.textContent=number(value);span.append(b);counts.append(span)};
  metric('Добавлено',j.uploaded);if(number(j.duplicates))metric('Уже есть',j.duplicates);if(number(j.total))metric('Найдено',j.total);if(number(j.failed))metric('Не удалось',j.failed,'failed');info.append(heading,counts);
  if(j.note){const note=document.createElement('p');note.className='job-note';note.textContent=j.note;info.append(note)}
  if(Number.isFinite(Number(j.created_at))){const time=document.createElement('small');time.className='job-time';time.textContent=new Date(Number(j.created_at)).toLocaleString('ru-RU');info.append(time)}
  badge.className='badge';badge.textContent=names[j.status]||j.status;row.append(info,badge);$('jobs').append(row);
 }
 if(!jobs.length)$('jobs').textContent='Здесь появится первое задание из Telegram.';
}
async function action(button,fn){button.disabled=true;notice('');try{await fn()}catch(e){notice(e.message)}finally{button.disabled=false}}
$('loginForm').addEventListener('submit',e=>{e.preventDefault();action(e.submitter,async()=>{const d=await request('/api/auth/login',{email:$('email').value.trim(),password:$('password').value});$('password').value='';session=d.token;sessionStorage.setItem(key,session);await refresh()})});
$('connectForm').addEventListener('submit',e=>{e.preventDefault();action(e.submitter,async()=>{await request('/api/import-admin',{action:'connect',token:$('botToken').value.trim()});$('botToken').value='';await refresh();notice('Бот подключён. Теперь привяжи свой Telegram.')})});
$('pairButton').addEventListener('click',()=>action($('pairButton'),async()=>{const d=await request('/api/import-admin',{action:'pair'});$('pairLink').href=d.link;$('pairLink').hidden=false;$('pairButton').hidden=true}));
$('refresh').addEventListener('click',()=>action($('refresh'),refresh));$('logout').addEventListener('click',async()=>{try{await request('/api/auth/logout',{})}catch{}session='';sessionStorage.removeItem(key);location.reload()});
refresh().catch(e=>notice(e.message));setInterval(()=>{if(!document.hidden&&session)refresh().catch(()=>{})},15000);

$('githubForm').addEventListener('submit',e=>{e.preventDefault();action(e.submitter,async()=>{await request('/api/import-admin',{action:'connectGithub',token:$('githubToken').value.trim()});$('githubToken').value='';await refresh();notice('Прямой запуск GitHub подключён.')})});$('wakeButton').addEventListener('click',()=>action($('wakeButton'),async()=>{await request('/api/import-admin',{action:'wake'});notice('Загрузчик запущен. Проверить результат можно через /status.')}));
