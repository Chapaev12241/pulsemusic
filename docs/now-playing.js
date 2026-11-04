/* One metadata owner: the system player always follows the current song. */
(()=>{
 let signature='';
 function update(request=true){
  if(!navigator.mediaSession||typeof MediaMetadata==='undefined')return;
  if(!current){signature='';navigator.mediaSession.metadata=null;return}
  const track=current,raw=track.artwork||window.PulseArtwork?.url(track.artist,track.title)||'';
  let src='';try{const u=new URL(raw,location.href);if(raw&&['https:','http:'].includes(u.protocol))src=u.href}catch{}
  const next=JSON.stringify([track.id,track.title,track.artist,track.album||'',src]);
  if(next!==signature){try{navigator.mediaSession.metadata=new MediaMetadata({title:track.title,artist:track.artist,album:track.album||'',artwork:src?[{src}]:[]});signature=next;document.dispatchEvent(new Event('pulse-now-playing'))}catch{}}
  if(!src&&request)window.PulseArtwork?.prioritize(track.artist,track.title);
 }
 window.PulseNowPlaying={update};
 for(const event of ['play','playing','loadedmetadata','pause'])audio.addEventListener(event,()=>update());
 for(const event of ['pulse-library','pulse-render','pulse-session','pulse-artwork'])document.addEventListener(event,()=>update(false));
 document.addEventListener('visibilitychange',()=>update(false));
 update(false);
})();
