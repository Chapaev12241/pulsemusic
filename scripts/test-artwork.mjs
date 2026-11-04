import vm from 'node:vm';import assert from 'node:assert/strict';import{readFileSync}from'node:fs';
const scope={};vm.runInNewContext(readFileSync('worker/artwork.mjs','utf8')+'\nthis.choose=chooseCover;',scope);
const items=[{artistName:'Other',trackName:'My song',artworkUrl100:'wrong'},{artistName:'Artist',trackName:'My song (Live)',artworkUrl100:'live'},{artistName:'Artist',trackName:'My Song',artworkUrl100:'correct'}];
assert.equal(scope.choose(items,'Artist','My song').artworkUrl100,'correct');assert.equal(scope.choose(items,'Artist','My song (Live)').artworkUrl100,'live');assert.equal(scope.choose(items,'Unknown','My song'),undefined);
assert.equal(scope.choose([{artistName:'Первый & Второй',trackName:'Полет',artworkUrl100:'duet'}],'Первый, Второй','Полёт').artworkUrl100,'duet');
console.log('PASS: artwork title/artist matching, edition distinction, wrong-artist rejection and collaboration normalization');
