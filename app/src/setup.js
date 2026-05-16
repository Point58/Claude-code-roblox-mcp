"use strict";

const fs = require("node:fs");
const path = require("node:path");
const {
  robloxPluginsDir,
  bundledPluginPath,
  installedPluginPath,
  claudeConfigPath,
  serverExePath,
} = require("./paths");

const SETTING_URL_LINE = 'local SETTING_URL = "ClaudeRobloxBridge_Url"';
const SETTING_TOKEN_LINE = 'local SETTING_TOKEN = "ClaudeRobloxBridge_Token"';
const AUTOCONNECT_MARKER = "--[[ AUTOCONNECT_INJECTION ]]";

// Patches the plugin source so it auto-loads the bundled token + url instead
// of waiting for the user to click Config. Idempotent: re-running with new
// values replaces the previous injection.
function injectPluginAutoconfig(source, token, port) {
  const injection = [
    AUTOCONNECT_MARKER,
    `pcall(function() plugin:SetSetting("ClaudeRobloxBridge_Token", ${JSON.stringify(token)}) end)`,
    `pcall(function() plugin:SetSetting("ClaudeRobloxBridge_Url", ${JSON.stringify(`http://127.0.0.1:${port}`)}) end)`,
    "",
  ].join("\n");

  if (source.includes(AUTOCONNECT_MARKER)) {
    return source.replace(
      new RegExp(`${AUTOCONNECT_MARKER}[\\s\\S]*?\\n\\n`, "m"),
      injection + "\n",
    );
  }
  // Inject right before the toolbar creation so the settings are present
  // when the plugin reads them.
  return source.replace(
    /local toolbar = plugin:CreateToolbar/,
    `${injection}\nlocal toolbar = plugin:CreateToolbar`,
  );
}

function installPlugin({ token, port }) {
  const src = bundledPluginPath();
  if (!src) throw new Error("Bundled plugin file not found in app resources.");
  const dst = installedPluginPath();
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  const source = fs.readFileSync(src, "utf8");
  const patched = injectPluginAutoconfig(source, token, port);
  fs.writeFileSync(dst, patched, "utf8");
  return dst;
}

function pluginInstalled() {
  return fs.existsSync(installedPluginPath());
}

// Edit ~/.claude.json — same shape Claude Code's `claude mcp add` writes.
// We use stdio + the bundled exe so users don't need Node installed.
function registerMcp({ token }) {
  const exe = serverExePath();
  if (!exe) throw new Error("Server binary not found.");

  const configPath = claudeConfigPath();
  let config = {};
  if (fs.existsSync(configPath)) {
    try {
      config = JSON.parse(fs.readFileSync(configPath, "utf8"));
    } catch {
      throw new Error(`Could not parse ${configPath} — file may be corrupted.`);
    }
  }
  if (!config.mcpServers) config.mcpServers = {};

  const serverEntry =
    exe.kind === "exe"
      ? { type: "stdio", command: exe.path, args: [], env: { CLAUDE_ROBLOX_TOKEN: token } }
      : { type: "stdio", command: "node", args: [exe.path], env: { CLAUDE_ROBLOX_TOKEN: token } };

  config.mcpServers.roblox = serverEntry;
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2), "utf8");
  return configPath;
}

function mcpRegistered() {
  const configPath = claudeConfigPath();
  if (!fs.existsSync(configPath)) return false;
  try {
    const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
    return Boolean(config.mcpServers && config.mcpServers.roblox);
  } catch {
    return false;
  }
}

function unregisterMcp() {
  const configPath = claudeConfigPath();
  if (!fs.existsSync(configPath)) return;
  try {
    const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
    if (config.mcpServers) {
      delete config.mcpServers.roblox;
      fs.writeFileSync(configPath, JSON.stringify(config, null, 2), "utf8");
    }
  } catch {
    // Silently skip — user can regenerate.
  }
}

module.exports = {
  installPlugin,
  pluginInstalled,
  registerMcp,
  unregisterMcp,
  mcpRegistered,
  robloxPluginsDir,
};
