import {mkdirSync,chmodSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
export const MAX_BYTES=50*1024*1024;
export function privateDirectory(path){mkdirSync(path,{recursive:true,mode:0o700});chmodSync(path,0o700);return path}
export function dataDirectory(){return privateDirectory(join(tmpdir(),'pulse-import-worker'))}
