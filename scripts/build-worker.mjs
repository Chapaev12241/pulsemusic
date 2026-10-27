import {rmSync,mkdirSync,copyFileSync} from 'node:fs';
rmSync('dist',{recursive:true,force:true});mkdirSync('dist/server',{recursive:true});mkdirSync('dist/.openai',{recursive:true});copyFileSync('worker/index.js','dist/server/index.js');copyFileSync('.openai/hosting.json','dist/.openai/hosting.json');console.log('Built dist');
