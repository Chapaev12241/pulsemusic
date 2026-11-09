import http from 'node:http';
import net from 'node:net';
import {lookup} from 'node:dns/promises';
import {randomBytes,timingSafeEqual} from 'node:crypto';

export function publicIP(address){
  if(net.isIP(address)===4){const b=address.split('.').map(Number);return !(b[0]===0||b[0]===10||b[0]===127||b[0]>=224||(b[0]===100&&b[1]>=64&&b[1]<=127)||(b[0]===169&&b[1]===254)||(b[0]===172&&b[1]>=16&&b[1]<=31)||(b[0]===192&&(b[1]===168||b[1]===0))||(b[0]===198&&(b[1]===18||b[1]===19||b[1]===51&&b[2]===100))||(b[0]===203&&b[1]===0&&b[2]===113));}
  if(net.isIP(address)===6){const lower=address.toLowerCase();if(lower.includes('.'))return false;const first=parseInt(lower.split(':')[0]||'0',16);return first>=0x2000&&first<=0x3fff&&!/^2001:(?:0*:|0*db8:)/i.test(lower)&&!/^2002:/i.test(lower)}return false;
}
export function sourceURL(raw){let u;try{u=new URL(raw)}catch{throw Error('Нужна ссылка вида https://example.com/artist')}
  if(!['http:','https:'].includes(u.protocol)||u.username||u.password||raw.length>4096||!['','80','443'].includes(u.port))throw Error('Нужна публичная HTTP(S)-ссылка без пароля и нестандартного порта.');
  const host=u.hostname.replace(/^\[|\]$/g,'');if(host==='localhost'||host.endsWith('.localhost')||host.endsWith('.local')||host.endsWith('.internal')||net.isIP(host)&&!publicIP(host))throw Error('Нужен публичный адрес сайта.');u.hash='';return u;
}
export async function resolvePublic(host,resolver=lookup){host=host.replace(/^\[|\]$/g,'');const addresses=net.isIP(host)?[{address:host,family:net.isIP(host)}]:await resolver(host,{all:true,verbatim:true});if(!addresses.length||addresses.some(x=>!publicIP(x.address)))throw Error('Blocked private/local address');return addresses[0];}

// Every extractor/CDN request passes this local proxy. CONNECT keeps TLS intact;
// DNS is resolved once and the socket is pinned to the validated public address.
// Cookies, Pulse credentials and bot tokens are never passed to the downloader.
export async function createDownloadProxy({resolver=lookup}={}){
  const password=randomBytes(24).toString('hex'),authorization='Basic '+Buffer.from('pulse:'+password).toString('base64'),sockets=new Set();
  function authorized(req){const v=req.headers['proxy-authorization']||'';return Buffer.byteLength(v)===Buffer.byteLength(authorization)&&timingSafeEqual(Buffer.from(v),Buffer.from(authorization))}
  const server=http.createServer(async(req,res)=>{
    if(!authorized(req)){res.writeHead(407);res.end();return}
    try{const url=sourceURL(req.url);if(url.protocol!=='http:')throw Error('Use CONNECT');const target=await resolvePublic(url.hostname,resolver);const headers={...req.headers,host:url.host};delete headers['proxy-authorization'];delete headers['proxy-connection'];
      const remote=http.request({hostname:target.address,family:target.family,port:80,method:req.method,path:url.pathname+url.search,headers,timeout:30000},response=>{res.writeHead(response.statusCode,response.headers);response.pipe(res)});remote.on('timeout',()=>remote.destroy());remote.on('error',()=>{if(!res.headersSent)res.writeHead(502);res.end()});req.on('aborted',()=>remote.destroy());req.pipe(remote);
    }catch{res.writeHead(403);res.end('Public destinations only')}
  });
  server.on('connect',async(req,client,head)=>{
    client.on('error',()=>{});if(!authorized(req)){client.end('HTTP/1.1 407 Proxy Authentication Required\r\n\r\n');return}
    try{const url=sourceURL('https://'+req.url);if(url.port&&url.port!=='443')throw Error('Port');const target=await resolvePublic(url.hostname,resolver);const remote=net.connect({host:target.address,family:target.family,port:443});sockets.add(remote);sockets.add(client);remote.setTimeout(45000);remote.on('timeout',()=>remote.destroy());remote.on('error',()=>client.destroy());remote.on('close',()=>{sockets.delete(remote);client.destroy()});client.on('close',()=>{sockets.delete(client);remote.destroy()});remote.on('connect',()=>{client.write('HTTP/1.1 200 Connection Established\r\n\r\n');if(head.length)remote.write(head);client.pipe(remote);remote.pipe(client)});
    }catch{client.end('HTTP/1.1 403 Forbidden\r\n\r\n')}
  });
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve)});
  return {url:'http://pulse:'+password+'@127.0.0.1:'+server.address().port,close(){for(const socket of sockets)socket.destroy();server.close()}};
}
