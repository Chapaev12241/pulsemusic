const ORIGIN='https://pulse-vibe-music.desyatnichenkoiosyf2.chatgpt.site';
function trustedURL(value,offline){try{const url=new URL(value);return url.origin===ORIGIN||(url.protocol==='file:'&&url.href===offline)}catch{return false}}
function externalURL(value){try{const url=new URL(value);return url.protocol==='https:'&&!url.username&&!url.password}catch{return false}}
const actions=new Set(['minimize','maximize','close']);
module.exports={ORIGIN,trustedURL,externalURL,windowAction:value=>actions.has(value)};
