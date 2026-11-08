import {mkdirSync,writeFileSync,copyFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
const source='docs/icons/pulse-512.png';
const folder='ios/Pulse/Assets.xcassets/AppIcon.appiconset';
mkdirSync(folder,{recursive:true});
execFileSync('sips',['-z','1024','1024',source,'--out',folder+'/AppIcon.png']);
writeFileSync(folder+'/Contents.json',JSON.stringify({images:[{filename:'AppIcon.png',idiom:'universal',platform:'ios',size:'1024x1024'}],info:{author:'xcode',version:1}},null,2));
const macSource='docs/icons/pulse-mac.png';
const mac='ios/Pulse/MacAssets.xcassets/AppIcon.appiconset';
mkdirSync(mac,{recursive:true});
const images=[];
for(const size of [16,32,128,256,512])for(const scale of [1,2]){
 const filename=`icon-${size}-${scale}x.png`;
 execFileSync('sips',['-z',String(size*scale),String(size*scale),macSource,'--out',mac+'/'+filename]);
 images.push({filename,idiom:'mac',size:`${size}x${size}`,scale:`${scale}x`});
}
writeFileSync(mac+'/Contents.json',JSON.stringify({images,info:{author:'xcode',version:1}},null,2));

for(const name of ['Soledago.ttf','Docker One.ttf'])copyFileSync(name,'ios/Pulse/'+name);
copyFileSync('docs/artwork-index.json','ios/Pulse/artwork-index.json');
