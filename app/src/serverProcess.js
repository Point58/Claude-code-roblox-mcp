"use strict";

const { spawn } = require("node:child_process");
const { serverExePath } = require("./paths");

let proc = null;
let listeners = new Set();

function emit(event, payload) {
  for (const fn of listeners) {
    try { fn(event, payload); } catch {}
  }
}

function onEvent(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

function isRunning() {
  return proc !== null && proc.exitCode === null;
}

function start({ token, port }) {
  if (isRunning()) return { ok: true, alreadyRunning: true };
  const exe = serverExePath();
  if (!exe) return { ok: false, error: "Server binary not found." };

  const env = {
    ...process.env,
    CLAUDE_ROBLOX_TOKEN: token,
    CLAUDE_ROBLOX_PORT: String(port),
    CLAUDE_ROBLOX_HOST: "127.0.0.1",
  };

  proc = exe.kind === "exe"
    ? spawn(exe.path, [], { env, stdio: ["ignore", "pipe", "pipe"] })
    : spawn("node", [exe.path], { env, stdio: ["ignore", "pipe", "pipe"] });

  const tail = (stream, level) => {
    stream.on("data", (chunk) => {
      const text = chunk.toString("utf8");
      for (const line of text.split(/\r?\n/)) {
        if (line.trim()) emit("log", { level, line });
      }
    });
  };
  tail(proc.stdout, "info");
  tail(proc.stderr, "info"); // server logs to stderr by design

  proc.on("exit", (code, signal) => {
    emit("exit", { code, signal });
    proc = null;
  });
  proc.on("error", (err) => {
    emit("error", { message: err.message });
    proc = null;
  });

  return { ok: true };
}

function stop() {
  if (!isRunning()) return;
  proc.kill();
  proc = null;
}

module.exports = { start, stop, isRunning, onEvent };
