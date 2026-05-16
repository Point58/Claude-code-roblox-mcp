"use strict";

const $ = (id) => document.getElementById(id);
const bridge = window.bridge;

function setDot(el, kind) {
  el.classList.remove("good", "bad", "warn", "pending");
  el.classList.add(kind);
}

function setTabs() {
  for (const tab of document.querySelectorAll(".tab")) {
    tab.addEventListener("click", () => {
      for (const t of document.querySelectorAll(".tab")) t.classList.remove("active");
      tab.classList.add("active");
      const name = tab.dataset.tab;
      for (const p of document.querySelectorAll(".panel")) {
        p.classList.toggle("hidden", p.dataset.panel !== name);
      }
    });
  }
}

function renderPlugin(state) {
  const dot = $("dot-plugin");
  const body = $("body-plugin");
  const btn = $("btn-install-plugin");
  if (state.status.plugin) {
    setDot(dot, "good");
    body.textContent = `Installed at ${state.pluginPath}.`;
    btn.textContent = "Reinstall plugin";
  } else {
    setDot(dot, "bad");
    body.textContent = "Plugin not detected in your Roblox Plugins folder.";
    btn.textContent = "Install plugin";
  }
}

function renderMcp(state) {
  const dot = $("dot-mcp");
  const body = $("body-mcp");
  if (state.status.mcp) {
    setDot(dot, "good");
    body.textContent = "Registered. Claude Code will spawn the server on launch.";
  } else {
    setDot(dot, "bad");
    body.textContent = "Not registered. Claude Code can't see the Roblox tools yet.";
  }
}

function renderServer(state) {
  const dot = $("dot-server");
  const body = $("body-server");
  const btn = $("btn-toggle-server");
  const s = state.status.server;
  if (s === "running") {
    setDot(dot, "good");
    body.textContent = `Listening on http://127.0.0.1:${state.port}.`;
    btn.textContent = "Stop server";
    btn.dataset.action = "stop";
  } else if (s === "unauthorized") {
    setDot(dot, "warn");
    body.textContent = "Server running but token mismatch. Try regenerating the token.";
    btn.textContent = "Start server";
    btn.dataset.action = "start";
  } else if (s === "unreachable") {
    setDot(dot, "bad");
    body.textContent = "Not running. Claude Code will start it automatically when you open a session.";
    btn.textContent = "Start server";
    btn.dataset.action = "start";
  } else {
    setDot(dot, "warn");
    body.textContent = s;
    btn.textContent = "Start server";
    btn.dataset.action = "start";
  }
}

function renderSettings(state) {
  $("input-token").value = state.token;
  $("input-port").value = state.port;
  $("input-plugins").value = state.pluginPath;
}

function appendLog(line) {
  const view = $("log-view");
  if (!view) return;
  const ts = new Date(line.ts).toLocaleTimeString();
  view.textContent += `${ts}  ${line.line}\n`;
  view.scrollTop = view.scrollHeight;
}

async function refresh() {
  const state = await bridge.getState();
  renderPlugin(state);
  renderMcp(state);
  renderServer(state);
  renderSettings(state);
  return state;
}

async function withBusy(button, fn) {
  const orig = button.textContent;
  button.disabled = true;
  button.textContent = "Working…";
  try {
    await fn();
  } catch (err) {
    alert(err.message || String(err));
  } finally {
    button.disabled = false;
    button.textContent = orig;
    await refresh();
  }
}

function bindActions() {
  $("btn-install-plugin").addEventListener("click", (e) => {
    withBusy(e.currentTarget, () => bridge.installPlugin());
  });
  $("btn-open-plugins").addEventListener("click", () => bridge.openPluginsFolder());

  $("btn-register-mcp").addEventListener("click", (e) => {
    withBusy(e.currentTarget, () => bridge.registerMcp());
  });
  $("btn-open-config").addEventListener("click", () => bridge.openConfigFile());

  $("btn-toggle-server").addEventListener("click", (e) => {
    const action = e.currentTarget.dataset.action;
    withBusy(e.currentTarget, async () => {
      if (action === "stop") await bridge.stopServer();
      else await bridge.startServer();
      // Give the OS a moment to bind the socket before re-checking.
      await new Promise((r) => setTimeout(r, 400));
    });
  });

  $("btn-copy-token").addEventListener("click", () => {
    navigator.clipboard.writeText($("input-token").value);
  });
  $("btn-regenerate-token").addEventListener("click", async (e) => {
    if (!confirm("Regenerate token? This reinstalls the plugin and updates Claude Code config.")) return;
    withBusy(e.currentTarget, () => bridge.regenerateToken());
  });

  $("btn-clear-logs").addEventListener("click", () => { $("log-view").textContent = ""; });
}

setTabs();
bindActions();
bridge.onLog((line) => appendLog(line));
bridge.onServerExit((info) => {
  appendLog({ ts: Date.now(), line: `--- server exited (code=${info.code}) ---` });
  refresh();
});

refresh();
setInterval(refresh, 4000);
