"use strict";

const http = require("node:http");
const fs = require("node:fs");
const { installedPluginPath } = require("./paths");
const { mcpRegistered } = require("./setup");

// HEAD/GET /health on 127.0.0.1:port. Returns one of:
//   "running"    — server responded, plugin handshake state unknown yet
//   "unreachable"— no server bound, ECONNREFUSED
//   "unauthorized"— server bound but token mismatch (HTTP 401)
//   "error: ..." — anything else
function checkServer({ port, token, timeoutMs = 1500 }) {
  return new Promise((resolve) => {
    const req = http.request(
      {
        host: "127.0.0.1",
        port,
        path: "/health",
        method: "GET",
        headers: { Authorization: `Bearer ${token}` },
        timeout: timeoutMs,
      },
      (res) => {
        // drain
        res.on("data", () => {});
        res.on("end", () => {
          if (res.statusCode === 200) resolve("running");
          else if (res.statusCode === 401) resolve("unauthorized");
          else resolve(`error: HTTP ${res.statusCode}`);
        });
      },
    );
    req.on("error", (err) => {
      if (err.code === "ECONNREFUSED") resolve("unreachable");
      else resolve(`error: ${err.code || err.message}`);
    });
    req.on("timeout", () => {
      req.destroy();
      resolve("error: timeout");
    });
    req.end();
  });
}

function snapshot({ port, token }) {
  return Promise.all([checkServer({ port, token })]).then(([server]) => ({
    server,
    plugin: fs.existsSync(installedPluginPath()),
    mcp: mcpRegistered(),
  }));
}

module.exports = { checkServer, snapshot };
