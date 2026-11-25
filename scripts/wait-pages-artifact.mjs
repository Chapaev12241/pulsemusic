const {GITHUB_API_URL='https://api.github.com',GITHUB_REPOSITORY,GITHUB_RUN_ID,PULSE_PAGES_ARTIFACT,PULSE_PAGES_TOKEN}=process.env;
if(!GITHUB_REPOSITORY||!GITHUB_RUN_ID||!PULSE_PAGES_ARTIFACT||!PULSE_PAGES_TOKEN)throw Error('Missing Pages artifact context');
for(let attempt=0;attempt<15;attempt++){
 const response=await fetch(`${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}/artifacts?per_page=100`,{headers:{authorization:`Bearer ${PULSE_PAGES_TOKEN}`,accept:'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28'},signal:AbortSignal.timeout(10000)});
 if(!response.ok)throw Error('Cannot read Pages artifact metadata: HTTP '+response.status);
 const data=await response.json();
 if(data.artifacts?.some(a=>a.name===PULSE_PAGES_ARTIFACT&&!a.expired)){console.log('Pages artifact is available.');process.exit(0)}
 await new Promise(resolve=>setTimeout(resolve,2000));
}
throw Error('Pages artifact metadata is not visible yet; retry this job');
