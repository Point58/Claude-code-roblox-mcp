"use strict";

const { app, BrowserWindow, ipcMain, shell, dialog } = require("electron");
const path = require("node:path");
const config = require("./config");
const setup = require("./setup");
const status = require("./status");
const serverProcess = require("./serverProcess");

let mainWindow = null;
const recentLogs = [];
const MAX_LOGS = 200;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 880,
    height: 620,
    minWidth: 720,
    minHeight: 520,
    backgroundColor: "#0e0f12",
    autoHideMenuBar: true,
    title: "Claude Roblox Bridge",
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  });
  mainWindow.loadFile(path.join(__dirname, "ui", "index.html"));
  mainWindow.on("closed", () => { mainWindow = null; });
  // DevTools open on startup so users can see console errors during early
  // versions. Remove when the app stabilizes.
  mainWindow.webContents.openDevTools({ mode: "detach" });
}

serverProcess.onEvent((event, payload) => {
  if (event === "log") {
    recentLogs.push({ ts: Date.now(), ...payload });
    if (recentLogs.length > MAX_LOGS) recentLogs.shift();
    if (mainWindow) mainWindow.webContents.send("log", { ts: Date.now(), ...payload });
  } else if (event === "exit") {
    if (mainWindow) mainWindow.webContents.send("server-exit", payload);
  }
});

ipcMain.handle("get-state", async () => {
  const cfg = config.read();
  const token = config.ensureToken();
  const stat = await status.snapshot({ port: cfg.port, token });
  return {
    token,
    port: cfg.port,
    autoStartServer: cfg.autoStartServer,
    pluginPath: setup.robloxPluginsDir(),
    serverRunning: serverProcess.isRunning(),
    status: stat,
    logs: recentLogs.slice(-60),
  };
});

ipcMain.handle("install-plugin", async () => {
  const cfg = config.read();
  const token = config.ensureToken();
  const dst = setup.installPlugin({ token, port: cfg.port });
  config.update({ pluginInstalled: true });
  return { ok: true, path: dst };
});

ipcMain.handle("register-mcp", async () => {
  const token = config.ensureToken();
  const path = setup.registerMcp({ token });
  config.update({ mcpRegistered: true });
  return { ok: true, path };
});

ipcMain.handle("unregister-mcp", async () => {
  setup.unregisterMcp();
  config.update({ mcpRegistered: false });
  return { ok: true };
});

ipcMain.handle("start-server", async () => {
  const cfg = config.read();
  const token = config.ensureToken();
  return serverProcess.start({ token, port: cfg.port });
});

ipcMain.handle("stop-server", async () => {
  serverProcess.stop();
  return { ok: true };
});

ipcMain.handle("regenerate-token", async () => {
  const crypto = require("node:crypto");
  const next = crypto.randomBytes(16).toString("hex");
  config.update({ token: next });
  // Re-install plugin so the new token is embedded.
  setup.installPlugin({ token: next, port: config.read().port });
  if (setup.mcpRegistered()) setup.registerMcp({ token: next });
  serverProcess.stop();
  return { ok: true, token: next };
});

ipcMain.handle("open-external", async (_e, url) => {
  await shell.openExternal(url);
});

ipcMain.handle("open-plugins-folder", async () => {
  await shell.openPath(setup.robloxPluginsDir());
});

ipcMain.handle("open-config-file", async () => {
  const { claudeConfigPath } = require("./paths");
  await shell.openPath(claudeConfigPath());
});

app.whenReady().then(() => {
  // Ensure token exists from first launch.
  config.ensureToken();
  createWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", () => {
  serverProcess.stop();
  if (process.platform !== "darwin") app.quit();
});

app.on("before-quit", () => { serverProcess.stop(); });
