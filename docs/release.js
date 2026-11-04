(()=>{
 const button=document.getElementById('updateApp'),label=document.getElementById('appVersion');
 if(!button||!label)return;
 const build=Number(label.dataset.build);
 button.onclick=async()=>{
  button.disabled=true;button.textContent='Проверяем обновление…';
  try{
   const request=new URL('./release.json',location.href);request.searchParams.set('_',Date.now());
   const response=await fetch(request,{cache:'no-store'});if(!response.ok)throw Error();
   const release=await response.json();if(!Number.isSafeInteger(release.build)||release.build<build)throw Error();
   const url=new URL(location.href);url.searchParams.set('build',String(release.build));url.searchParams.set('_refresh',String(Date.now()));
   location.replace(url.href);
  }catch{button.disabled=false;button.textContent='Повторить обновление';toast('Не удалось проверить обновление. Проверь подключение.')}
 };
})();
