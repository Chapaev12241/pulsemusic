import {mkdirSync,chmodSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
export const MAX_BYTES=50*1024*1024;
export function privateDirectory(path){mkdirSync(path,{recursive:true,mode:0o700});chmodSync(path,0o700);return path}
export function dataDirectory(){return privateDirectory(join(tmpdir(),'pulse-import-worker'))}

export function previewAudioURL(raw){try{const u=new URL(raw),path=decodeURIComponent(u.pathname);return u.hostname==='p.scdn.co'||/(?:^|\/)(?:mp3-preview|previews?|snippets?)(?:\/|$)/i.test(path)}catch{return true}}
