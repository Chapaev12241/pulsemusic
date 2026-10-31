import {mkdirSync,writeFileSync} from 'node:fs';
const base='https://cdn.jsdelivr.net/npm/jsmediatags@3.9.7/';
mkdirSync('docs/vendor',{recursive:true});
for(const [remote,local] of [['dist/jsmediatags.min.js','jsmediatags.min.js'],['LICENSE.md','jsmediatags-LICENSE.md']]){const r=await fetch(base+remote);if(!r.ok)throw Error('Tag reader download failed: '+r.status);writeFileSync('docs/vendor/'+local,await r.text())}
console.log('Pinned jsmediatags 3.9.7 saved locally');
