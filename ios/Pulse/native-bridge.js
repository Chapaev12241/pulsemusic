// Bundled only in the iOS application. The public website keeps its existing player.
(() => {
  if (location.origin !== 'https://chapaev12241.github.io' || !location.pathname.startsWith('/pulsemusic/')) return;
  function install() {
    if (!window.PulseLibrary || !document.querySelector('#djEnabled')) return;
    if (window.PulseNativeReceive) return;
    const send = body => window.webkit.messageHandlers.pulse.postMessage(body);
    let native = {paused: true, time: 0, duration: 0}, source = '', volume = .8;
    const event = name => audio.dispatchEvent(new Event(name));
    Object.defineProperties(audio, {
      paused: {get: () => native.paused}, ended: {get: () => false},
      currentTime: {get: () => native.time, set: time => send({action: 'seek', time})},
      duration: {get: () => native.duration}, readyState: {get: () => native.duration ? 4 : 0},
      src: {get: () => source, set: value => {source = value}}, currentSrc: {get: () => source},
      volume: {get: () => volume, set: value => {volume = value; send({action:'volume', value})}}
    });
    audio.load = () => {};
    audio.play = async () => {
      const ids = queue.length ? queue : tracks.map(t => t.id);
      send({action: 'play', id: current?.id, token, dj: $('#djEnabled').checked,
        tracks: ids.map(id => tracks.find(t => t.id === id)).filter(Boolean).map(t => ({id:t.id,title:t.title,artist:t.artist,audio:t.audio,album:t.album||'',artwork:t.artwork||PulseArtwork.url?.(t.artist,t.title)||''}))});
    };
    audio.pause = () => send({action:'pause'});
    setupAudio = () => { $('#audioStatus').textContent = 'Нативный iOS-плеер · фоновый звук'; };
    $('#next').onclick = () => send({action:'next'});
    $('#previous').onclick = () => send({action:'previous'});
    const dj = $('#djEnabled');
    dj.disabled = false;
    dj.checked = localStorage.getItem('pulse_dj') !== 'off';
    dj.onchange = () => {localStorage.setItem('pulse_dj', dj.checked?'on':'off');send({action:'dj',enabled:dj.checked})};
    $('#djStatus').textContent = 'Нативное плавное сведение · 3 секунды';
    // History is recorded by the native clock even while the web view is suspended.
    window.PulseNativeReceive = message => {
      if(message.historySaved){if(!document.hidden && token) refresh().catch(()=>{});return}
      if(message.error){$('#playerStatus').textContent=message.error;return}
      const previous = native;
      native = message;
      if(current?.id !== message.id){
        const track = tracks.find(t => t.id === message.id);
        if(track){current=track;window.PulseNowPlaying?.update();source=track.audio;$('#nowTitle').textContent=track.title;$('#nowArtist').textContent=track.artist;$('.now>.art').outerHTML=PulseArtwork.markup(track.artist,track.title)}
      }
      historyRecorded = true;
      if(previous.paused !== native.paused) event(native.paused?'pause':'play');
      event('timeupdate');
      $('#playerStatus').textContent = message.buffering?'Загрузка…':'';
    };
    document.addEventListener('pulse-session',()=>send({action:'stop'}));
    document.addEventListener('visibilitychange',()=>{if(!document.hidden)send({action:'state'})});
    volume = Number($('#volume').value);send({action:'volume',value:volume});send({action:'state'});
  }
  if(document.readyState === 'loading')document.addEventListener('DOMContentLoaded',install,{once:true});else install();
})();
