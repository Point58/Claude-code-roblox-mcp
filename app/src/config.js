"use strict";

const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const { appConfigPath } = require("./paths");

const DEFAULTS = {
  token: null,
  port: 31416,
  autoStartServer: true,
  pluginInstalled: false,
  mcpRegistered: false,
};

function ensureDir(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

function read() {
  const p = appConfigPath();
  if (!fs.existsSync(p)) return { ...DEFAULTS };
  try {
    return { ...DEFAULTS, ...JSON.parse(fs.readFileSync(p, "utf8")) };
  } catch {
    return { ...DEFAULTS };
  }
}

function write(cfg) {
  const p = appConfigPath();
  ensureDir(p);
  fs.writeFileSync(p, JSON.stringify(cfg, null, 2), "utf8");
}

function ensureToken() {
  const cfg = read();
  if (!cfg.token) {
    cfg.token = crypto.randomBytes(16).toString("hex");
    write(cfg);
  }
  return cfg.token;
}

function update(patch) {
  const cfg = { ...read(), ...patch };
  write(cfg);
  return cfg;
}

module.exports = { read, write, ensureToken, update };
