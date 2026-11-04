(()=>{
 let selected='',release=null,all=false,displayed=[];
 function art(a,kind='artist-art'){
  if(PulseArtwork.url(a.name,''))return PulseArtwork.markup(a.name,'',kind);
  const track=a.tracks.find(t=>t.artwork||PulseArtwork.url(t.artist,t.title))||a.tracks[0];
  return track?PulseArtwork.markup(track.artist,track.title,kind).replace(/data-art-artist="[^"]*" data-art-title="[^"]*"/,()=>`data-art-artist="${safe(a.name)}" data-art-title=""`):'';
 }
 function popular(a){const scores=new Map();for(const h of state.history||[])scores.set(h.id,(scores.get(h.id)||0)+1);return [...a.tracks].sort((x,y)=>(scores.get(y.id)||0)-(scores.get(x.id)||0)||Number(state.liked.includes(y.id))-Number(state.liked.includes(x.id))||x.title.localeCompare(y.title,'ru'))}
 function releases(a){const groups=new Map();for(const t of a.tracks){const key=t.album?.trim()||'';if(!groups.has(key))groups.set(key,{name:key||'Синглы',key,tracks:[]});groups.get(key).tracks.push(t)}return [...groups.values()].sort((a,b)=>a.name.localeCompare(b.name,'ru'))}
 function render(a,list){
  if(selected!==a.key){selected=a.key;release=null;all=false}
  $('#artistPortrait').innerHTML=art(a,'artist-portrait');
  PulseArtwork.prioritize(a.name,'');
  $('#artistName').textContent=a.name;
  const ids=new Set(a.tracks.map(t=>t.id)),recent=(state.history||[]).filter(h=>ids.has(h.id)&&Date.now()-Date.parse(h.at)<7*864e5).length;
  $('#artistStats').textContent=PulseLibrary.count(a.tracks.length)+(recent?' · '+recent+' '+(recent%10===1&&recent%100!==11?'прослушивание':recent%10>=2&&recent%10<=4&&(recent%100<12||recent%100>14)?'прослушивания':'прослушиваний')+' за неделю':'');
  if(!a.genres.length)$('#artistGenres').textContent='';
  const group=releases(a).find(g=>g.key===release);if(release!==null&&!group)release=null;
  displayed=release!==null?group.tracks:popular(a);
  $('#artistTracksTitle').textContent=release!==null?group.name:all?'Все треки':'Популярное у тебя';
  $('#artistShowAll').hidden=release!==null?false:a.tracks.length<=5;
  $('#artistShowAll').textContent=release!==null?'Все треки':all?'Свернуть':'Все треки';
  rows('#artistTracks',release!==null||all?displayed:displayed.slice(0,5));
  $('#artistReleases').innerHTML=releases(a).map((g,i)=>`<button class="artist-release${release===g.key?' selected':''}" data-artist-release="${i}" aria-pressed="${release===g.key}">${PulseArtwork.markup(g.tracks[0].artist,g.tracks[0].title)}<b>${safe(g.name)}</b><small>${safe(PulseLibrary.count(g.tracks.length))}</small></button>`).join('');
  const genres=new Set(a.genres.map(PulseMusic.normalize));
  const related=list.filter(b=>b.key!==a.key).map(b=>({a:b,score:b.genres.filter(g=>genres.has(PulseMusic.normalize(g))).length})).filter(b=>b.score>0).sort((a,b)=>b.score-a.score).slice(0,8);
  $('#artistRelatedSection').hidden=!related.length;
  $('#artistRelated').innerHTML=related.map(({a:b})=>`<button class="artist-card compact" data-artist="${safe(b.key)}">${art(b)}<b>${safe(b.name)}</b><small>${safe(PulseLibrary.count(b.tracks.length))}</small></button>`).join('');
  $('#shuffleArtist').onclick=()=>playArtist(a,true);
 }
 function playArtist(a,shuffle=false){const list=selected===a.key&&displayed.length?[...displayed]:popular(a);if(shuffle)for(let i=list.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));[list[i],list[j]]=[list[j],list[i]]}queue=list.map(t=>t.id);if(queue.length)play(queue[0])}
 function openCurrent(){if(!current)return;const a=PulseMusic.artists(tracks).find(a=>a.tracks.some(t=>t.id===current.id));if(!a)return;document.getElementById('nowPlaying')?.close();document.body.classList.remove('player-expanded');activeArtist=a.key;view('artists');PulseLibrary.render()}
 document.addEventListener('click',e=>{
  if(e.target.closest('#artistBack')){activeArtist=null;view('search');PulseLibrary.render()}
  if(e.target.closest('#artistShowAll')){if(release!==null){release=null;all=true}else all=!all;PulseLibrary.render()}
  const button=e.target.closest('[data-artist-release]');if(button){const a=PulseMusic.artists(tracks).find(a=>a.key===activeArtist),g=a&&releases(a)[Number(button.dataset.artistRelease)];if(g){release=release===g.key?null:g.key;all=false;PulseLibrary.render();$('#artistTracksTitle').scrollIntoView({behavior:document.documentElement.dataset.motion==='off'?'instant':'smooth',block:'start'})}}
  if(e.target.closest('#npArtist'))openCurrent();
 });
 window.PulseArtist={art,render,play:playArtist,ids:()=>displayed.map(t=>t.id),popular,releases};
 // app.js can finish its initial render before this deferred module is installed.
 PulseLibrary.render();
})();
