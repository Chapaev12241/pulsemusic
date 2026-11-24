/* Disk-backed audio downloads. Two network jobs at once; playback always wins. */
(()=>{
 const available=!!window.caches&&window.isSecureContext;
 const setting='pulse_auto_download_likes';
 let owner='',epoch=0,indexWrites=Promise.resolve(),ready=Promise.resolve(),saved=new Map(),waiting=[],running=new Map(),preloadIDs=new Set(),playlistQueue='',inFlight=new Map(),notifiedQuota=false;
 const urls=new Map(),MAX_FILE=50*1024*1024;
 const scope=()=>user?.id||(token?localStorage.getItem('pulse_download_owner'):'')||'guest';
 const names=()=>({saved:'pulse-audio-saved-v1:'+owner,preload:'pulse-audio-preload-v1:'+owner});
 const key=id=>new URL('/__pulse_audio__/'+encodeURIComponent(id),location.origin).href;
 const stateOwnerKey='pulse_download_state:';
 const indexKey=new URL('/__pulse_audio_index__',location.origin).href;
 const valid=t=>t&&/^[a-f0-9]{64}$/i.test(t.id)&&(()=>{try{const u=new URL(t.audio);return u.protocol==='https:'&&u.origin===new URL(API).origin&&!u.username&&!u.password}catch{return false}})();
 const notify=()=>document.dispatchEvent(new Event('pulse-downloads'));
 function index(n=names(),values=[...saved.values()]){if(!available)return Promise.resolve();indexWrites=indexWrites.catch(()=>{}).then(async()=>{const cache=await caches.open(n.saved);await cache.put(indexKey,new Response(JSON.stringify(values),{headers:{'Content-Type':'application/json'}}))});return indexWrites}
 function switchOwner(){if(user?.id)localStorage.setItem('pulse_download_owner',user.id);const next=scope();if(next===owner)return ready;owner=next;const stamp=++epoch;waiting.splice(0).forEach(j=>j.resolve(false));for(const job of running.values())job.controller.abort();running.clear();inFlight.clear();preloadIDs.clear();playlistQueue='';saved.clear();for(const {url}of urls.values())URL.revokeObjectURL(url);urls.clear();notifiedQuota=false;
  ready=(async()=>{if(!available)return;try{const cache=await caches.open(names().saved),data=await cache.match(indexKey);const list=data?await data.json():[];if(stamp!==epoch)return;for(const t of list)if(valid(t)&&await cache.match(key(t.id)))saved.set(t.id,t);notify();hydrate()}catch{}})();return ready;
 }
 function hydrate(){if(navigator.onLine||!saved.size)return;try{const cached=JSON.parse(localStorage.getItem(stateOwnerKey+owner)||'null');if(cached&&Array.isArray(cached.playlists)&&Array.isArray(cached.liked))state={...state,...cached}}catch{};const known=new Set(tracks.map(t=>t.id));for(const t of saved.values())if(!known.has(t.id))tracks.push(t);if(!tracks.length)return;render();document.dispatchEvent(new Event('pulse-library'))}
 async function trimPreload(cache,keep=preloadIDs){for(const request of await cache.keys()){const id=decodeURIComponent(new URL(request.url).pathname.split('/').pop());if(!keep.has(id))await cache.delete(request)}}
 async function transfer(job){const stamp=job.epoch,n=job.names;const permanent=await caches.open(n.saved),temporary=await caches.open(n.preload);let response=await permanent.match(key(job.track.id))||await temporary.match(key(job.track.id));if(!response){
   const estimate=await navigator.storage?.estimate?.().catch(()=>null);if(estimate?.quota&&estimate.quota-estimate.usage<MAX_FILE+16*1024*1024){await trimPreload(temporary,new Set());if(job.permanent)throw Object.assign(Error('Недостаточно места для скачивания'),{name:'QuotaExceededError'});return false}
   const headers=new Headers();if(job.token)headers.set('Authorization','Bearer '+job.token);
   response=await fetch(job.track.audio,{headers,signal:job.controller.signal,credentials:'omit',cache:'no-store'});
   if(!response.ok||response.status!==200||!/^audio\//i.test(response.headers.get('Content-Type')||''))throw Error('Аудиофайл недоступен');
   const size=Number(response.headers.get('Content-Length'));if(size>MAX_FILE)throw Error('Аудиофайл больше 50 МБ');
  }
  if(stamp!==epoch||job.controller.signal.aborted)return false;
  const destinationPermanent=job.permanent;const target=destinationPermanent?permanent:temporary;
  // Cache.put streams the response to disk instead of creating a full JS audio buffer.
  await target.put(key(job.track.id),response);
  if(stamp!==epoch){await target.delete(key(job.track.id));return false}
  if(destinationPermanent){saved.set(job.track.id,job.track);await temporary.delete(key(job.track.id));await index(n)}else if(!job.permanent&&!preloadIDs.has(job.track.id)){await temporary.delete(key(job.track.id))}
  return true;
 }
 function pump(){while(running.size<2&&waiting.length){waiting.sort((a,b)=>a.priority-b.priority||a.order-b.order);const job=waiting.shift();if(job.epoch!==epoch){job.resolve(false);continue}running.set(job.track.id,job);(async()=>{let ok=false;try{ok=await transfer(job);if(ok&&job.permanent&&!saved.has(job.track.id)){// A preload may have been promoted while Cache.put was streaming.
     const temp=await caches.open(job.names.preload),response=await temp.match(key(job.track.id));if(response&&job.epoch===epoch){const cache=await caches.open(job.names.saved);await cache.put(key(job.track.id),response);saved.set(job.track.id,job.track);await temp.delete(key(job.track.id));await index(job.names)}}
   }catch(e){if(e.name==='QuotaExceededError'){if(job.permanent&&!notifiedQuota){toast('Недостаточно места. Освободи память и повтори скачивание.');notifiedQuota=true}}else if(job.permanent&&e.name!=='AbortError')job.error=e.message}finally{if(running.get(job.track.id)===job)running.delete(job.track.id);if(inFlight.get(job.track.id)===job)inFlight.delete(job.track.id);job.resolve(ok);notify();pump()}})()}}
 let order=0;
 async function enqueue(track,permanent=false,priority=2){const intended=scope();await switchOwner();await ready;if(owner!==intended||scope()!==intended)return false;if(!available||!valid(track))return false;if(saved.has(track.id))return true;
  const existing=inFlight.get(track.id);if(existing){existing.permanent ||= permanent;existing.priority=Math.min(existing.priority,priority);return existing.promise}
  const job={track,permanent,priority,order:order++,epoch,names:names(),token,controller:new AbortController()};job.promise=new Promise(resolve=>job.resolve=resolve);inFlight.set(track.id,job);waiting.push(job);notify();pump();return job.promise;
 }
 function prepare(ids,id,{all=false}={}){if(!available||window.PulseNativeReceive)return;switchOwner();const signature=ids.join(',');if(all)playlistQueue=signature;else if(playlistQueue!==signature)playlistQueue='';const index=ids.indexOf(id),rotated=index<0?ids:[...ids.slice(index+1),...ids.slice(0,index+1)],chosen=all||playlistQueue===signature?rotated:rotated.slice(0,1);preloadIDs=new Set(chosen);
  waiting=waiting.filter(job=>{if(job.permanent||preloadIDs.has(job.track.id))return true;inFlight.delete(job.track.id);job.resolve(false);return false});
  for(const job of running.values())if(!job.permanent&&!preloadIDs.has(job.track.id))job.controller.abort();
  for(const [i,next]of chosen.entries()){const track=tracks.find(t=>t.id===next);if(track)enqueue(track,false,i===0?0:3)}
  ready.then(async()=>{const cache=await caches.open(names().preload);await trimPreload(cache)}).catch(()=>{});
 }
 async function resolve(track){await switchOwner();await ready;if(!available||window.PulseNativeReceive||!valid(track))return track.audio;const cached=urls.get(track.id);if(cached)return cached.url;const stamp=epoch,n=names();try{const permanent=await caches.open(n.saved),temporary=await caches.open(n.preload),response=await permanent.match(key(track.id))||await temporary.match(key(track.id));if(!response)return track.audio;const blob=await response.blob();if(stamp!==epoch)return track.audio;const url=URL.createObjectURL(blob);urls.set(track.id,{url,at:Date.now()});while(urls.size>3){const old=urls.keys().next().value;if(old===track.id)break;URL.revokeObjectURL(urls.get(old).url);urls.delete(old)}return url}catch{return track.audio}}
 function status(list){const validTracks=list.filter(valid),done=validTracks.filter(t=>saved.has(t.id)).length,pending=validTracks.filter(t=>inFlight.get(t.id)?.permanent).length;return {total:validTracks.length,done,pending}}
 async function downloadAll(list){if(!available){toast('Скачивание недоступно в этом браузере');return}const intended=scope();await switchOwner();await ready;if(owner!==intended||scope()!==intended)return;try{await navigator.storage?.persist?.()}catch{}const selected=[...new Map(list.filter(valid).map(t=>[t.id,t])).values()];if(!selected.length)return;const results=await Promise.all(selected.map(t=>enqueue(t,true,1)));if(!results.every(Boolean))toast('Часть треков не скачалась. Нажми «Скачать всё» ещё раз.');else toast('Плейлист скачан')}
 const panel=document.createElement('section');panel.className='panel';panel.innerHTML='<h3>Музыка на устройстве</h3><label class="setting">Скачивать при нажатии ♡<input type="checkbox" id="autoDownloadLikes"></label><p class="muted">Следующий трек подгружается заранее. Плейлисты — целиком, по очереди.</p><p class="muted" id="downloadStatus" role="status" aria-live="polite"></p>';
 $('#settings .settings-grid').append(panel);const toggle=$('#autoDownloadLikes');toggle.checked=localStorage.getItem(setting)==='on';toggle.disabled=!available;toggle.onchange=()=>{localStorage.setItem(setting,toggle.checked?'on':'off');if(toggle.checked){const liked=tracks.filter(t=>state.liked.includes(t.id));downloadAll(liked)}};
 function paint(){const count=[...inFlight.values()].filter(j=>j.permanent).length;$('#downloadStatus').textContent=!available?'Браузер не поддерживает сохранение аудио.':count?'Скачивается: '+count+' · Сохранено: '+saved.size:'Сохранено на устройстве: '+saved.size}
 document.addEventListener('pulse-render',()=>{if(navigator.onLine&&owner===scope()&&(!token||user))try{localStorage.setItem(stateOwnerKey+owner,JSON.stringify({liked:state.liked,playlists:state.playlists,playlistCovers:state.playlistCovers||{}}))}catch{}});
 document.addEventListener('pulse-downloads',paint);document.addEventListener('pulse-profile',()=>switchOwner());document.addEventListener('pulse-session',()=>switchOwner());window.addEventListener('offline',hydrate);window.addEventListener('online',()=>{notifiedQuota=false});
 window.PulseDownloads={resolve,prepare,status,downloadAll,liked:track=>{if(localStorage.getItem(setting)==='on')enqueue(track,true,1).then(ok=>{if(!ok)toast('Не удалось скачать трек. Повтори из плейлиста.')})},get tracks(){return [...saved.values()]}};
 if('serviceWorker'in navigator&&!window.PulseNativeReceive){const source=new URL(document.currentScript?.src||'./downloads.js',location.href),worker=new URL('./offline-worker.js',source);worker.search=source.search;navigator.serviceWorker.register(worker.href,{scope:new URL('./',source).pathname,updateViaCache:'none'}).catch(()=>{})}
 switchOwner();paint();
})();
