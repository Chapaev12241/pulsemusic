import {mkdirSync,writeFileSync} from 'node:fs';
// Run on the macOS builder. sips is supplied with macOS; no npm dependency.
import {execFileSync} from 'node:child_process';
const folder='ios/Pulse/Assets.xcassets/AppIcon.appiconset';
mkdirSync(folder,{recursive:true});
execFileSync('sips',['-z','1024','1024','docs/icons/pulse-512.png','--out',folder+'/AppIcon.png']);
writeFileSync(folder+'/Contents.json',JSON.stringify({images:[{filename:'AppIcon.png',idiom:'universal',platform:'ios',size:'1024x1024'}],info:{author:'xcode',version:1}},null,2));
