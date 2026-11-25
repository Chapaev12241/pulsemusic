// Use the documented Pages REST deployment API with the exact uploaded artifact ID.
// The stock action discovers artifacts through a different (Twirp) service first.
import {appendFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';

export async function deployPages(env=process.env,{request=fetch,sleep=ms=>new Promise(r=>setTimeout(r,ms)),now=Date.now,log=console.log,writeOutput=line=>appendFileSync(env.GITHUB_OUTPUT,line),timeoutMs=600000,intervalMs=5000,signal}={}){
 const {GITHUB_REPOSITORY:repo,GITHUB_SHA:sha,PULSE_PAGES_ARTIFACT_ID:rawID,PULSE_PAGES_TOKEN:token,ACTIONS_ID_TOKEN_REQUEST_TOKEN:requestToken,ACTIONS_ID_TOKEN_REQUEST_URL:requestURL}=env;
 const api=env.GITHUB_API_URL||'https://api.github.com';
 if(api!=='https://api.github.com'||!repo||!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo)||!sha||!/^[a-f0-9]{40}$/i.test(sha)||!rawID||!/^\d+$/.test(rawID)||!Number.isSafeInteger(Number(rawID))||Number(rawID)<1||!token||!requestToken||!requestURL||!env.GITHUB_OUTPUT)throw Error('Missing or invalid Pages deployment context');
 let oidcURL;try{oidcURL=new URL(requestURL)}catch{throw Error('Invalid Actions OIDC endpoint')}
 if(oidcURL.protocol!=='https:'||!oidcURL.hostname.endsWith('.actions.githubusercontent.com')||oidcURL.username||oidcURL.password||oidcURL.port||oidcURL.hash)throw Error('Invalid Actions OIDC endpoint');
 const headers={authorization:'Bearer '+token,accept:'application/vnd.github+json','content-type':'application/json','X-GitHub-Api-Version':'2022-11-28'};
 const base=api+'/repos/'+repo+'/pages/deployments';let deploymentID='',statusEndpoint='',succeeded=false;
 async function json(url,options={},label='GitHub Pages',withSignal=true){
  let response;try{response=await request(url,{...options,redirect:'error',signal:withSignal&&signal?AbortSignal.any([signal,AbortSignal.timeout(20000)]):AbortSignal.timeout(20000)})}catch{const error=Error(label+' network request failed');error.status=signal?.aborted?499:504;throw error}
  if(!response.ok){const error=Error(label+' returned HTTP '+response.status);error.status=response.status;throw error}
  try{return await response.json()}catch{throw Error(label+' returned invalid JSON')}
 }
 async function cancel(){if(!deploymentID||succeeded)return;try{await request((statusEndpoint||base+'/'+deploymentID)+'/cancel',{method:'POST',headers,redirect:'error',signal:AbortSignal.timeout(10000)});log('Requested cancellation of unfinished Pages deployment.')}catch{log('Could not cancel unfinished Pages deployment.')}}
 try{
  const identity=await json(oidcURL.href,{headers:{authorization:'Bearer '+requestToken}},'Actions OIDC');
  if(typeof identity.value!=='string'||!identity.value)throw Error('Actions OIDC did not return a token');
  if(signal?.aborted)throw Error('Pages deployment cancelled');
  const deployment=await json(base,{method:'POST',headers,body:JSON.stringify({artifact_id:Number(rawID),pages_build_version:sha,oidc_token:identity.value})});
  // Record a recoverable reference immediately, so validation failures can cancel
  // a deployment that the API has already created.
  const returnedID=String(deployment.id||sha);
  deploymentID=/^[A-Za-z0-9_-]{1,120}$/.test(returnedID)?returnedID:sha;
  let statusURL;try{statusURL=deployment.status_url?new URL(deployment.status_url):null}catch{throw Error('Pages returned an invalid deployment status URL')}
  if(statusURL){
   const named=statusURL.pathname.match(/^\/repos\/([^/]+)\/([^/]+)\/pages\/deployments\/([A-Za-z0-9_-]{1,120})$/i);
   const numbered=statusURL.pathname.match(/^\/repositories\/([1-9]\d*)\/pages\/deployments\/([A-Za-z0-9_-]{1,120})$/i);
   const scoped=named?((named[1]+'/'+named[2]).toLowerCase()===repo.toLowerCase()):!!(numbered&&env.GITHUB_REPOSITORY_ID&&numbered[1]===env.GITHUB_REPOSITORY_ID);
   if(statusURL.origin!==api||!scoped||statusURL.search||statusURL.hash||statusURL.username||statusURL.password){
    log('Rejected Pages status endpoint: '+statusURL.origin+statusURL.pathname.slice(0,200));
    throw Error('Pages returned an invalid deployment status URL');
   }
   deploymentID=named?named[3]:numbered[2];
   statusEndpoint=statusURL.href;
  }else{statusEndpoint=base+'/'+deploymentID}
  let pageURL;try{pageURL=new URL(deployment.page_url)}catch{throw Error('Pages did not return a site URL')}
  if(!['https:','http:'].includes(pageURL.protocol)||pageURL.username||pageURL.password)throw Error('Pages returned an invalid site URL');
  log('Created Pages deployment from the uploaded artifact.');
  const deadline=now()+Math.min(600000,Math.max(1,timeoutMs)),finalErrors=new Set(['deployment_failed','deployment_perms_error','deployment_content_failed','deployment_cancelled','deployment_lost']);let errors=0,lastStatus='';
  while(now()<deadline){
   if(signal?.aborted)throw Error('Pages deployment cancelled');
   let status;
   try{status=await json(statusEndpoint,{headers});errors=0}catch(error){if(signal?.aborted||!([404,429,504].includes(error.status)||error.status>=500)||++errors>=10)throw error;log('Pages status temporarily unavailable; retrying.');await sleep(intervalMs);continue}
   if(status.status==='succeed'){succeeded=true;writeOutput('page_url='+pageURL.href+'\n');log('Pages deployment succeeded.');return {page_url:pageURL.href,id:deploymentID,status:'succeed'}}
   if(finalErrors.has(status.status))throw Error('Pages deployment ended with '+status.status);
   if(status.status!==lastStatus){lastStatus=status.status;log('Waiting for Pages deployment.');}
   await sleep(intervalMs);
  }
  throw Error('Pages deployment timed out');
 }catch(error){await cancel();throw error}
}

if(process.argv[1]&&pathToFileURL(resolve(process.argv[1])).href===import.meta.url){
 const controller=new AbortController();
 for(const name of ['SIGINT','SIGTERM'])process.once(name,()=>controller.abort());
 deployPages(process.env,{signal:controller.signal}).catch(error=>{console.error('Pages deployment failed: '+error.message);process.exitCode=1});
}
