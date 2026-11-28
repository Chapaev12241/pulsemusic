/* A playlist-picker excerpt never becomes the main transport or listening history. */
(()=>{
 function interval(duration){
  if(!Number.isFinite(duration)||duration<=1)throw Error('Не удалось определить длительность трека');
  const start=Math.max(.25,Math.min(duration*.38,duration-.5)),end=Math.min(duration-.1,start+15);
  if(end<=start)throw Error('Трек слишком короткий для отрывка');
  return {start,end};
 }
 function create({main,context,resolveSource=async t=>t.audio,api,origin,onState=()=>{},makeAudio=()=>new Audio(),timeoutMs=15000,timers={setTimeout,clearTimeout}}){
  let state={id:'',status:'idle',error:''},generation=0,clip=null,controller=null,timer=null,suspended=null,wrappedPause=null,originalPause=null,destroyed=false;
  const identity=()=>context(),same=(a,b)=>a.owner===b.owner&&a.track===b.track&&a.source===b.source&&a.remote===b.remote;
  function publish(value){state={...value};onState({...state})}
  function restorePause(){if(wrappedPause&&main.pause===wrappedPause)main.pause=originalPause;wrappedPause=originalPause=null}
  function discard(){controller?.abort();controller=null;if(timer!==null){timers.clearTimeout(timer);timer=null}if(clip){const old=clip;clip=null;old.pause();old.removeAttribute('src');old.load()}restorePause()}
  function stop({resume=true,error=''}={}){
   ++generation;discard();const hold=suspended;suspended=null;publish({id:'',status:error?'error':'idle',error});
   if(resume&&hold?.resume&&same(hold.context,identity())&&main.paused&&!main.ended&&!identity().remote){try{Promise.resolve(main.play()).catch(()=>{})}catch{}}
  }
  function holdMain(){
   if(!suspended)suspended={context:identity(),resume:!main.paused&&!main.ended&&!identity().remote};
   originalPause=main.pause;const savedPause=originalPause;
   wrappedPause=function(...args){if(suspended)stop({resume:false});return savedPause.apply(main,args)};
   main.pause=wrappedPause;
   // Call the saved method so only an external pause cancels restoration.
   savedPause.call(main);
  }
  function wait(media,events,condition,signal){return new Promise((resolve,reject)=>{
   let deadline;
   const clear=()=>{for(const name of events)media.removeEventListener(name,check);media.removeEventListener('error',failed);signal.removeEventListener('abort',aborted);if(deadline!==undefined)timers.clearTimeout(deadline)};
   const check=()=>{if(condition()){clear();resolve()}};
   const failed=()=>{clear();reject(Error('Не удалось загрузить отрывок. Проверь подключение.'))};
   const aborted=()=>{clear();reject(Error('Preview cancelled'))};
   for(const name of events)media.addEventListener(name,check);media.addEventListener('error',failed);signal.addEventListener('abort',aborted,{once:true});deadline=timers.setTimeout(failed,timeoutMs);if(signal.aborted)aborted();else check();
  })}
  async function toggle(track){
   if(destroyed)return;
   if(state.id===track.id&&['loading','playing'].includes(state.status)){stop();return}
   const request=++generation;discard();holdMain();controller=new AbortController();const signal=controller.signal;
   publish({id:track.id,status:'loading',error:''});
   try{
    const initial=new URL(track.audio,api);if(initial.protocol!=='https:'||initial.origin!==new URL(api).origin||initial.username||initial.password)throw Error('Этот трек недоступен для отрывка');
    const source=await resolveSource(track);if(request!==generation||destroyed)return;
    const url=new URL(source,api);if(!((url.protocol==='https:'&&url.origin===new URL(api).origin)||(url.protocol==='blob:'&&url.origin===origin))||url.username||url.password)throw Error('Этот трек недоступен для отрывка');
    const media=makeAudio();clip=media;media.preload='auto';media.crossOrigin='anonymous';media.playsInline=true;media.muted=true;media.volume=main.muted?0:Math.min(1,Math.max(0,main.volume));media.src=url.href;media.load();
    await wait(media,['loadedmetadata','durationchange'],()=>media.readyState>=1&&Number.isFinite(media.duration)&&media.duration>1,signal);
    if(request!==generation||clip!==media)return;
    const range=interval(media.duration);
    const seeked=wait(media,['seeked','loadeddata','canplay'],()=>!media.seeking&&Math.abs(media.currentTime-range.start)<.3,signal);media.currentTime=range.start;
    // Metadata can be cached and a seek can finish synchronously.
    if(!media.seeking&&Math.abs(media.currentTime-range.start)<.3)media.dispatchEvent(new Event('seeked'));
    await seeked;if(request!==generation||clip!==media)return;
    media.addEventListener('timeupdate',()=>{if(request===generation&&media.currentTime>=range.end)stop()});
    media.addEventListener('ended',()=>{if(request===generation)stop()});
    media.addEventListener('error',()=>{if(request===generation)stop({error:'Не удалось воспроизвести отрывок. Попробуй ещё раз.'})});
    media.muted=false;await media.play();if(request!==generation||clip!==media){media.pause();return}
    publish({id:track.id,status:'playing',error:'',start:range.start,end:range.end});timer=timers.setTimeout(()=>{if(request===generation)stop()},(range.end-range.start)*1000+750);
   }catch(error){if(request===generation&&!signal.aborted)stop({error:error.message||'Отрывок недоступен. Попробуй ещё раз.'})}
  }
  function sync(){if(suspended&&!same(suspended.context,identity()))stop({resume:false})}
  const mainIntent=()=>{if(suspended)stop({resume:false})},volume=()=>{if(clip)clip.volume=main.muted?0:Math.min(1,Math.max(0,main.volume))};
  for(const event of ['play','emptied','seeking','ended','error'])main.addEventListener(event,mainIntent);main.addEventListener('volumechange',volume);
  return {toggle,stop,sync,intent:mainIntent,get state(){return {...state}},destroy(){if(destroyed)return;stop({resume:false});destroyed=true;for(const event of ['play','emptied','seeking','ended','error'])main.removeEventListener(event,mainIntent);main.removeEventListener('volumechange',volume)}};
 }
 window.PulseTrackPreview={create,interval};
})();
