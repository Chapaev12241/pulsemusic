// Interactive metadata search. Callback payloads contain only opaque, expiring choices.
const IMPORT_THEMES={
 japan:{name:'Японская музыка',options:[['J-pop','j-pop'],['J-rock','j-rock'],['Опенинги аниме','anime openings'],['Vocaloid','vocaloid']]},
 korea:{name:'Корейская музыка',options:[['K-pop','k-pop'],['Корейский хип-хоп','korean hip hop'],['Корейский инди','korean indie'],['Корейский рок','korean rock']]},
 anime:{name:'Аниме',options:[['Опенинги аниме','anime openings'],['Эндинги аниме','anime endings'],['Саундтреки аниме','anime soundtrack']]}
};
function importTheme(text){const q=importArtistKey(importSongQuery(text));if(/^(?:аниме|анисон|anime|anisong|анимемузыка|музыкаизаниме)$/.test(q))return 'anime';if(/^(?:японск(?:ое|ая|ую|ие|ой|ом)(?:музык[ауи]|песни|треки)?|japan(?:ese)?(?:music)?)$/.test(q))return 'japan';if(/^(?:корейск(?:ое|ая|ую|ие|ой|ом)(?:музык[ауи]|песни|треки)?|korean?(?:music)?)$/.test(q))return 'korea';return null}
function importWantsDiscovery(text){
 if(!text||/^(?:бери два|бери 2|оба|обоих|бери оба|бери обоих|[12]|второй|второго|первый|первого)$/iu.test(text))return false;
 if(/^\/(?:track|song|style|genre)(?:@\w+)?(?:\s|$)/i.test(text))return true;
 if(text.startsWith('/')||/https?:\/\/|(?:[\p{L}\d-]+\.)+[\p{L}]{2,}\//iu.test(text))return false;
 if(/(?:все|всю)\s+(?:песни|треки|музыку|дискографию)|^(?:загрузи|скачай|добавь|импортируй)\s+(?:песни|треки|дискографию)|^(?:исполнитель|артист)\s/iu.test(text))return false;
 try{if(importParse(text).source!=='https://tunemir.com/')return false}catch{return false}
 return true;
}
function importSongQuery(text){return String(text).normalize('NFKC').replace(/^\/(?:track|song|style|genre)(?:@\w+)?\s*/i,'').replace(/^(?:(?:пожалуйста|пж|плиз|хочу|мне|подбери|подобрать|покажи|посоветуй|найди|найти|скачай|скачать|добавь|добавить|загрузи|загрузить)\s+){1,6}/iu,'').replace(/^(?:песню|трек|песня|музыку|подборку|стиль|жанр)\s+/iu,'').replace(/^[\s«»"']+|[\s«»"']+$/gu,'').trim().slice(0,120)}
async function importDiscoveryJSON(path){
 const url=new URL(path,'https://api.deezer.com');if(url.origin!=='https://api.deezer.com')throw Error('Недопустимый адрес поиска');
 const response=await fetch(url.href,{signal:AbortSignal.timeout(9000),headers:{accept:'application/json'}});if(!response.ok)throw Error('Поиск временно недоступен. Попробуй позже.');
 const text=await response.text();if(text.length>2*1024*1024)throw Error('Слишком большой ответ поиска');let data;try{data=JSON.parse(text)}catch{throw Error('Поиск временно недоступен. Попробуй позже.')};if(data.error||!Array.isArray(data.data))throw Error('Поиск временно недоступен. Попробуй позже.');return data.data;
}
const importChoiceKey=owner=>'import-choices/v1/'+owner;
async function importSaveChoice(env,cfg,chat,updateID,kind,query,choices){
 const value={nonce:crypto.randomUUID().replaceAll('-','').slice(0,20),owner:cfg.owner_id,chat,updateID,kind,query,choices,expires:Date.now()+15*60000};
 await env.BUCKET.put(importChoiceKey(cfg.owner_id),JSON.stringify(value),{httpMetadata:{contentType:'application/json'}});return value;
}
const importChoiceButton=(choice,index,state)=>({text:Array.from(choice.label).slice(0,60).join(''),callback_data:'pi:'+state.nonce+':'+index});
async function importEnableChoiceCallbacks(env,cfg){
 const key='import-choice-webhook/v1/'+cfg.owner_id,fingerprint=await importHash(cfg.username+'|'+cfg.token_cipher+'|'+cfg.webhook_secret),marker=await env.BUCKET.get(key);
 if(marker&&await marker.text()===fingerprint)return;
 const token=await importDecrypt(env,cfg.token_cipher),info=await importTelegram(token,'getWebhookInfo',{});let url;try{url=new URL(info.url)}catch{throw Error('Подключи webhook бота в настройках Pulse Import.')}
 if(url.protocol!=='https:'||url.pathname!=='/api/import-bot/webhook'||!['pulse-vibe-music.desyatnichenkoiosyf2.chatgpt.site','music-pulse.ru'].includes(url.hostname))throw Error('Адрес бота изменился. Подключи его заново в Pulse Import.');
 await importTelegram(token,'setWebhook',{url:url.href,secret_token:cfg.webhook_secret,allowed_updates:['message','callback_query'],drop_pending_updates:false});
 await env.BUCKET.put(key,fingerprint);
}
async function importShowChoice(env,cfg,chat,updateID,kind,query,choices,title){await importEnableChoiceCallbacks(env,cfg);const state=await importSaveChoice(env,cfg,chat,updateID,kind,query,choices);await importTell(env,cfg,chat,title,{inline_keyboard:choices.map((c,i)=>[importChoiceButton(c,i,state)])})}
async function importSearchSong(env,cfg,chat,updateID,query,offset=0){
 if(!query)throw Error('Напиши название песни, например: /track Blue Bird');
 const rows=await importDiscoveryJSON('/search/track?'+new URLSearchParams({q:query,limit:'8',index:String(offset)}));
 const exact=rows.filter(t=>importArtistKey(t.title_short||t.title)===importArtistKey(query));const source=exact.length?exact:rows;const seen=new Set(),choices=[];
 for(const t of source){if(!/^\d+$/.test(String(t.id))||!t.title||!t.artist?.name||cleanEdition(t.title))continue;const key=importArtistKey(t.artist.name);if(seen.has(key))continue;seen.add(key);choices.push({label:t.artist.name+(exact.length?'':' — '+t.title),source:'https://www.deezer.com/track/'+t.id,artist:t.artist.name,title:t.title});if(choices.length===8)break;}
 if(offset>0)choices.push({label:'Предыдущие исполнители',action:'songMore',query,offset:Math.max(0,offset-8)});
 if(rows.length===8&&offset<992)choices.push({label:'Ещё исполнители',action:'songMore',query,offset:offset+8});
 choices.push({label:'Это исполнитель — загрузить все треки',action:'artist',query});
 await importShowChoice(env,cfg,chat,updateID,'song',query,choices,choices.length>1?'«'+query+'» — от какого исполнителя?\nВыбери один трек:':'Песню «'+query+'» не нашёл. Можно загрузить каталог исполнителя:');
}
async function importShowThemes(env,cfg,chat,updateID,key){
 const theme=IMPORT_THEMES[key];const choices=theme?theme.options.map(([label,query])=>({label,action:'style',query})):[{label:'Японская музыка',action:'theme',query:'japan'},{label:'Корейская музыка',action:'theme',query:'korea'},{label:'Опенинги аниме',action:'style',query:'anime openings'},{label:'Джаз',action:'style',query:'jazz'},{label:'Рок',action:'style',query:'rock'},{label:'Lo-fi',action:'style',query:'lofi'}];
 await importShowChoice(env,cfg,chat,updateID,'theme',key||'',choices,theme?theme.name+' — что подобрать?':'Какую музыку подобрать?');
}
async function importSearchStyle(env,cfg,chat,updateID,query,offset=0){
 const rows=await importDiscoveryJSON('/search/playlist?'+new URLSearchParams({q:query,limit:'6',index:String(offset)}));const choices=[];
 for(const p of rows){if(!/^\d+$/.test(String(p.id))||!p.title)continue;choices.push({label:p.title+(Number(p.nb_tracks)>0?' · '+p.nb_tracks+' тр.':''),source:'https://www.deezer.com/playlist/'+p.id,artist:'',title:p.title});if(choices.length===6)break;}
 if(!choices.length)throw Error('Подборок больше нет. Выбери одну из предыдущих или попробуй другой жанр.');
 if(offset>0)choices.push({label:'Предыдущие подборки',action:'style',query,offset:Math.max(0,offset-6)});
 if(rows.length===6&&offset<996)choices.push({label:'Ещё подборки',action:'style',query,offset:offset+6});
 await importShowChoice(env,cfg,chat,updateID,'style',query,choices,'Подборки по теме «'+query+'». Выбери одну — загружу весь доступный список, без обрезки до 20 треков.');
}
async function importStartDiscovery(env,cfg,chat,updateID,text){
 const command=text.match(/^\/(style|genre)(?:@\w+)?(?:\s|$)/i),query=importSongQuery(text),theme=importTheme(text);
 if(/^\/(?:track|song)(?:@\w+)?(?:\s|$)/i.test(text))return importSearchSong(env,cfg,chat,updateID,query);
 const direct=[[/опенинг|anime[ -]?opening/iu,'anime openings'],[/эндинг|anime[ -]?ending/iu,'anime endings'],[/^(?:j[ -]?pop)$/iu,'j-pop'],[/^(?:j[ -]?rock)$/iu,'j-rock'],[/^(?:k[ -]?pop)$/iu,'k-pop'],[/^(?:vocaloid|вокалоид)$/iu,'vocaloid']];
 for(const [pattern,value]of direct)if(pattern.test(query))return importSearchStyle(env,cfg,chat,updateID,value);
 if(command&&!query)return importShowThemes(env,cfg,chat,updateID,null);
 if(theme)return importShowThemes(env,cfg,chat,updateID,theme);
 if(command)return importSearchStyle(env,cfg,chat,updateID,query);
 const moods={джаз:'jazz',jazz:'jazz',рок:'rock',rock:'rock',lofi:'lofi',лофай:'lofi',рэп:'rap',реп:'rap',rap:'rap',хипхоп:'hip hop',трэп:'trap',треп:'trap',метал:'metal',metal:'metal',фонк:'phonk',эмбиент:'ambient',классика:'classical'};const mood=moods[importArtistKey(query)];if(mood)return importSearchStyle(env,cfg,chat,updateID,mood);
 return importSearchSong(env,cfg,chat,updateID,query);
}
async function importChoiceCallback(r,env,cfg,update){
 const q=update.callback_query,msg=q?.message,chat=String(msg?.chat?.id||'');
 if(!q?.id||msg?.chat?.type!=='private'||String(q.from?.id)!==chat||cfg.telegram_id!==chat||!Number.isSafeInteger(update.update_id)||!await importOwner(env,cfg.owner_id))return json(r,{ok:true});
 const token=await importDecrypt(env,cfg.token_cipher);await importTelegram(token,'answerCallbackQuery',{callback_query_id:q.id}).catch(()=>{});
 try{
  const match=String(q.data||'').match(/^pi:([a-f0-9]{20}):(\d{1,2})$/);if(!match)throw Error('Неизвестная кнопка. Напиши название трека ещё раз.');
  const object=await env.BUCKET.get(importChoiceKey(cfg.owner_id));const choiceState=object?JSON.parse(await object.text()):null;
  if(!choiceState||choiceState.owner!==cfg.owner_id||choiceState.chat!==chat||choiceState.expires<Date.now()||choiceState.nonce!==match[1])throw Error('Этот выбор устарел. Напиши запрос ещё раз.');
  const selected=choiceState.choices?.[Number(match[2])];if(!selected)throw Error('Вариант не найден. Напиши запрос ещё раз.');
  if(selected.action==='theme'){await importShowThemes(env,cfg,chat,choiceState.updateID,selected.query);return json(r,{ok:true})}
  if(selected.action==='style'){await importSearchStyle(env,cfg,chat,choiceState.updateID,selected.query,Number(selected.offset)||0);return json(r,{ok:true})}
  if(selected.action==='songMore'){await importSearchSong(env,cfg,chat,choiceState.updateID,selected.query,Number(selected.offset)||0);return json(r,{ok:true})}
  const parsed=selected.action==='artist'?importParse('/artist '+selected.query):{source:importSourceURL(selected.source),artist:selected.artist||''};
  const prior=await env.DB.prepare('SELECT id FROM pulse_import_jobs WHERE update_id=?').bind(choiceState.updateID).first();if(prior)throw Error('Этот выбор уже добавлен в очередь. /status — ход загрузки.');
  const count=await env.DB.prepare("SELECT COUNT(*) AS n FROM pulse_import_jobs WHERE owner_id=? AND status IN ('queued','running')").bind(cfg.owner_id).first();if(count.n>=10)throw Error('В очереди уже 10 заданий. Дождись завершения или используй /cancel');
  const now=Date.now();const inserted=await env.DB.prepare('INSERT INTO pulse_import_jobs(id,update_id,owner_id,chat_id,source,artist,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(update_id) DO NOTHING').bind(crypto.randomUUID(),choiceState.updateID,cfg.owner_id,chat,parsed.source,parsed.artist,now,now).run();
  if(!inserted.meta.changes)throw Error('Этот выбор уже добавлен в очередь.');
  await importTelegram(token,'editMessageReplyMarkup',{chat_id:chat,message_id:msg.message_id,reply_markup:{inline_keyboard:[]}}).catch(()=>{});
  const kick=await importKick(env,cfg);let reply='Добавлено в очередь: '+(selected.title||selected.query||parsed.artist)+'.\n'+(choiceState.kind==='song'&&selected.source?'Загружаю только выбранный трек.':'Загружаю доступные полные записи.');if(kick.missing)reply+='\nПодключи GitHub в настройках Pulse Import для запуска без ожидания.';else if(!kick.ok)reply+='\nПроверь автозапуск в настройках Pulse Import.';
  await importTell(env,cfg,chat,reply);
 }catch(e){await importTell(env,cfg,chat,e.message||'Не удалось обработать выбор. Повтори запрос.');}
 return json(r,{ok:true});
}
