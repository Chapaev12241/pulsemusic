const {contextBridge,ipcRenderer}=require('electron');
contextBridge.exposeInMainWorld('pulseDesktop',Object.freeze({
  platform:'windows',autoplay:true,
  info:()=>ipcRenderer.invoke('pulse:info'),
  minimize:()=>ipcRenderer.invoke('pulse:window','minimize'),
  maximize:()=>ipcRenderer.invoke('pulse:window','maximize'),
  close:()=>ipcRenderer.invoke('pulse:window','close'),
  retry:()=>ipcRenderer.invoke('pulse:retry'),
  windowState:()=>ipcRenderer.invoke('pulse:window-state'),
  onWindowState:callback=>{if(typeof callback!=='function')return()=>{};const listener=(_event,data)=>callback({maximized:!!data.maximized});ipcRenderer.on('pulse:window-state',listener);return()=>ipcRenderer.removeListener('pulse:window-state',listener)}
}));
