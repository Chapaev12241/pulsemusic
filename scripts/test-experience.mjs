import vm from 'node:vm';import assert from 'node:assert/strict';import{readFileSync}from'node:fs';
const node={addEventListener(){},dispatchEvent(){},children:[]},sandbox={window:{},document:{addEventListener(){}},$:()=>node,audio:node};
vm.runInNewContext(readFileSync('docs/lyrics.js','utf8'),sandbox);
const rows=sandbox.window.PulseLyrics.parse('[offset:-500]\n[00:01.00][00:03.20]First\n[00:02.00]Second\n[ar:Test]');
assert.equal(rows.length,3);assert.equal(rows[0].time,.5);assert.equal(rows[1].text,'Second');assert.equal(rows[2].time,2.7);
vm.runInNewContext(readFileSync('docs/karaoke.js','utf8'),sandbox);
const sample=sandbox.window.PulseKaraoke.sample;
assert(Math.abs(sample(1,1,0)[0]-.16)<1e-9);assert.equal(sample(1,-1,0)[0],1);assert.equal(sample(1,-1,0)[1],-1);assert(Math.abs(sample(1,1,.84)[0]-1)<1e-9);
console.log('PASS: LRC timestamps, multi-line timestamps, offset, stereo center reduction, side signal and bass preservation');
