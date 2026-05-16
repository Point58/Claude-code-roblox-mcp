"use strict";

const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("bridge", {
  getState: () => ipcRenderer.invoke("get-state"),
  installPlugin: () => ipcRenderer.invoke("install-plugin"),
  registerMcp: () => ipcRenderer.invoke("register-mcp"),
  unregisterMcp: () => ipcRenderer.invoke("unregister-mcp"),
  startServer: () => ipcRenderer.invoke("start-server"),
  stopServer: () => ipcRenderer.invoke("stop-server"),
  regenerateToken: () => ipcRenderer.invoke("regenerate-token"),
  openExternal: (url) => ipcRenderer.invoke("open-external", url),
  openPluginsFolder: () => ipcRenderer.invoke("open-plugins-folder"),
  openConfigFile: () => ipcRenderer.invoke("open-config-file"),
  onLog: (cb) => {
    const fn = (_e, line) => cb(line);
    ipcRenderer.on("log", fn);
    return () => ipcRenderer.removeListener("log", fn);
  },
  onServerExit: (cb) => {
    const fn = (_e, info) => cb(info);
    ipcRenderer.on("server-exit", fn);
    return () => ipcRenderer.removeListener("server-exit", fn);
  },
});
