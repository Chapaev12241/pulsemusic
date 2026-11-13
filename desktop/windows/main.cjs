const {app,BrowserWindow,ipcMain,shell,session}=require('electron');
const path=require('node:path'),os=require('node:os'),{pathToFileURL}=require('node:url');
const {ORIGIN,trustedURL,externalURL,windowAction}=require('./security.cjs');
const offline=pathToFileURL(path.join(__dirname,'offline.html')).href;
const smoke=process.argv.includes('--pulse-smoke-test');
app.commandLine.appendSwitch('autoplay-policy','no-user-gesture-required');
app.setAppUserModelId('com.chapaev12241.pulsemusic.windows');
let window,loaded=false;
if(!app.requestSingleInstanceLock()){app.quit()}else{
 app.on('second-instance',()=>{if(window){if(window.isMinimized())window.restore();window.show();window.focus()}});
 const authorized=event=>window&&event.sender===window.webContents&&event.senderFrame===window.webContents.mainFrame&&trustedURL(event.senderFrame.url,offline);
 ipcMain.handle('pulse:info',event=>{if(!authorized(event))throw Error('Untrusted frame');return{name:os.hostname().slice(0,80),platform:'windows',version:app.getVersion()}});
 ipcMain.handle('pulse:window',(event,action)=>{if(!authorized(event)||!windowAction(action))return false;if(action==='minimize')window.minimize();if(action==='maximize')window.isMaximized()?window.unmaximize():window.maximize();if(action==='close')window.close();return true});
 ipcMain.handle('pulse:window-state',event=>authorized(event)?{maximized:window.isMaximized()}:null);
 ipcMain.handle('pulse:retry',event=>{if(authorized(event))window.loadURL(ORIGIN) });
 app.whenReady().then(()=>{
  const partition=session.fromPartition('persist:pulse');
  partition.setPermissionRequestHandler((_contents,permission,callback)=>callback(['clipboard-sanitized-write','fullscreen'].includes(permission)));
  partition.setPermissionCheckHandler((_contents,permission)=>['clipboard-sanitized-write','fullscreen'].includes(permission));
  window=new BrowserWindow({width:1200,height:820,minWidth:880,minHeight:600,frame:false,show:false,backgroundColor:'#08080a',title:'Pulse',icon:path.join(__dirname,'assets/icon.png'),autoHideMenuBar:true,webPreferences:{preload:path.join(__dirname,'preload.cjs'),partition:'persist:pulse',sandbox:true,contextIsolation:true,nodeIntegration:false,webSecurity:true,allowRunningInsecureContent:false,backgroundThrottling:false}});
  window.setMenu(null);
  const publishState=()=>{if(window&&!window.isDestroyed())window.webContents.send('pulse:window-state',{maximized:window.isMaximized()})};
  window.on('maximize',publishState);window.on('unmaximize',publishState);
  window.once('ready-to-show',()=>{if(!smoke)window.show()});
  window.webContents.setWindowOpenHandler(({url})=>{if(externalURL(url))shell.openExternal(url);return{action:'deny'}});
  window.webContents.on('will-navigate',(event,url)=>{if(!trustedURL(url,offline)){event.preventDefault();if(externalURL(url))shell.openExternal(url)}});
  window.webContents.on('did-fail-load',(_event,_code,_text,url,isMainFrame)=>{if(isMainFrame&&url.startsWith(ORIGIN)&&!window.isDestroyed())window.loadFile(path.join(__dirname,'offline.html'))});
  window.webContents.on('did-finish-load',()=>{if(smoke){loaded=window.webContents.getURL().startsWith(ORIGIN);console.log(JSON.stringify({smoke:'Pulse Windows',loaded,version:app.getVersion(),electron:process.versions.electron}));app.exit(loaded?0:1)}});
  window.webContents.on('before-input-event',(event,input)=>{if(input.control&&input.type==='keyDown'&&input.key.toLowerCase()==='r'){event.preventDefault();window.loadURL(ORIGIN)}});
  window.on('closed',()=>{window=null});
  window.loadURL(ORIGIN).catch(()=>{});
  if(smoke)setTimeout(()=>app.exit(loaded?0:1),45000).unref();
 });
 app.on('window-all-closed',()=>app.quit());
}
