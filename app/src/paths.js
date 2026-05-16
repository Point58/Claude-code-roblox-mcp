"use strict";

const { app } = require("electron");
const path = require("node:path");
const os = require("node:os");
const fs = require("node:fs");

function homeDir() {
  return os.homedir();
}

// Roblox installs plugins to %LOCALAPPDATA%\Roblox\Plugins on Windows
// and ~/Documents/Roblox/Plugins on macOS.
function robloxPluginsDir() {
  if (process.platform === "win32") {
    const local = process.env.LOCALAPPDATA || path.join(homeDir(), "AppData", "Local");
    return path.join(local, "Roblox", "Plugins");
  }
  if (process.platform === "darwin") {
    return path.join(homeDir(), "Documents", "Roblox", "Plugins");
  }
  // Linux: best-effort (Wine/Sober). Users on Linux are rare for Studio.
  return path.join(homeDir(), ".local", "share", "Roblox", "Plugins");
}

function claudeConfigPath() {
  return path.join(homeDir(), ".claude.json");
}

function appConfigPath() {
  return path.join(app.getPath("userData"), "config.json");
}

// Path to bundled MCP server executable inside the installed app.
// In dev (npm start) we fall back to running the source via Node.
function serverExePath() {
  const candidate = process.resourcesPath
    ? path.join(process.resourcesPath, "claude-roblox-mcp.exe")
    : null;
  if (candidate && fs.existsSync(candidate)) {
    return { kind: "exe", path: candidate };
  }
  const devEntry = path.resolve(__dirname, "..", "..", "server", "dist", "index.js");
  if (fs.existsSync(devEntry)) {
    return { kind: "node", path: devEntry };
  }
  return null;
}

// Path to bundled plugin file (the one we copy into Roblox/Plugins).
function bundledPluginPath() {
  const candidate = process.resourcesPath
    ? path.join(process.resourcesPath, "ClaudeBridge.lua")
    : null;
  if (candidate && fs.existsSync(candidate)) return candidate;
  const dev = path.resolve(__dirname, "..", "..", "plugin-bundled", "ClaudeBridge.server.luau");
  if (fs.existsSync(dev)) return dev;
  return null;
}

function installedPluginPath() {
  return path.join(robloxPluginsDir(), "ClaudeBridge.lua");
}

module.exports = {
  homeDir,
  robloxPluginsDir,
  claudeConfigPath,
  appConfigPath,
  serverExePath,
  bundledPluginPath,
  installedPluginPath,
};
