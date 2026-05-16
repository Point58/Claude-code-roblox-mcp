"use strict";

// Wrap in IIFE — keeps everything out of the global scope, which avoids
// conflicting with `window.bridge` exposed by the preload script (Chrome
// treats top-level const/let names as global lexical bindings and refuses
// to redeclare a name that already exists on the global object).
(function () {
  console.log("[renderer] starting, bridge=", typeof window.bridge);

  const $ = (id) => document.getElementById(id);
  const api = window.bridge;

  if (!api) {
    document.body.innerHTML = `
      <div style="padding:40px;font-family:sans-serif;color:#ef4444;">
        <h1>Preload script failed to load</h1>
        <p>window.bridge is undefined — IPC layer is missing.</p>
        <p>Open DevTools (Ctrl+Shift+I) and check the Console tab for the root cause.</p>
      </div>`;
    throw new Error("preload not loaded");
  }

  function setBadge(el, kind, text) {
    if (!el) return;
    el.classList.remove("success", "warning", "danger", "info", "pending");
    if (kind) el.classList.add(kind);
    if (text != null) el.textContent = text;
  }

  function setDot(el, kind) {
    if (!el) return;
    el.classList.remove("good", "bad", "warn", "pending");
    el.classList.add(kind);
  }

  function setStepState(stepEl, state) {
    if (!stepEl) return;
    stepEl.classList.remove("done", "current", "todo");
    stepEl.classList.add(state);
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
    const body = $("body-plugin");
    const btn = $("btn-install-plugin");
    const badge = $("badge-plugin");
    if (state.status.plugin) {
      setBadge(badge, "success", "Installed");
      body.innerHTML = `Plugin file is at <code>${state.pluginPath}</code>. Token already embedded.`;
      btn.textContent = "Reinstall plugin";
      return true;
    }
    setBadge(badge, "danger", "Not installed");
    body.innerHTML = `Drops <code>ClaudeBridge.lua</code> into your Roblox Plugins folder, with the bridge token already embedded.`;
    btn.textContent = "Install plugin";
    return false;
  }

  function renderMcp(state) {
    const body = $("body-mcp");
    const badge = $("badge-mcp");
    const btn = $("btn-register-mcp");
    if (state.status.mcp) {
      setBadge(badge, "success", "Registered");
      body.innerHTML = `Claude Code can call the Roblox tools. Entry is in <code>~/.claude.json</code> and the server will be spawned on demand.`;
      btn.textContent = "Re-register";
      return true;
    }
    setBadge(badge, "danger", "Not registered");
    body.innerHTML = `Adds this bridge as an MCP server in <code>~/.claude.json</code> so Claude Code can call the Roblox tools.`;
    btn.textContent = "Register with Claude Code";
    return false;
  }

  function renderServer(state) {
    const dot = $("dot-server");
    const body = $("body-server");
    const btn = $("btn-toggle-server");
    const badge = $("badge-server");
    const s = state.status.server;
    if (s === "running") {
      setDot(dot, "good");
      setBadge(badge, "success", "Running");
      body.innerHTML = `Listening on <code>http://127.0.0.1:${state.port}</code>.`;
      btn.textContent = "Stop server";
      btn.dataset.action = "stop";
      return "running";
    }
    if (s === "unauthorized") {
      setDot(dot, "warn");
      setBadge(badge, "warning", "Token mismatch");
      body.innerHTML = `A bridge is running on port ${state.port} but uses a different token. Regenerate the token in <b>Settings</b> to fix it.`;
      btn.textContent = "Start server";
      btn.dataset.action = "start";
      return "warn";
    }
    if (s === "unreachable") {
      setDot(dot, "pending");
      setBadge(badge, "info", "Idle");
      body.innerHTML = `Not running. Claude Code will start it automatically when you open a session — you can also start it here to test.`;
      btn.textContent = "Start server";
      btn.dataset.action = "start";
      return "idle";
    }
    setDot(dot, "warn");
    setBadge(badge, "warning", "Unknown");
    body.textContent = s;
    btn.textContent = "Start server";
    btn.dataset.action = "start";
    return "warn";
  }

  function renderStepper(pluginDone, mcpDone) {
    const stepPlugin = $("step-plugin");
    const stepMcp = $("step-mcp");
    const stepStudio = $("step-studio");
    const studioBadge = $("badge-studio");

    if (pluginDone) {
      setStepState(stepPlugin, "done");
    } else {
      setStepState(stepPlugin, "current");
    }

    if (mcpDone) {
      setStepState(stepMcp, "done");
    } else if (pluginDone) {
      setStepState(stepMcp, "current");
    } else {
      setStepState(stepMcp, "todo");
    }

    if (pluginDone && mcpDone) {
      setStepState(stepStudio, "current");
      setBadge(studioBadge, "info", "Do this next");
    } else {
      setStepState(stepStudio, "todo");
      setBadge(studioBadge, "pending", "Waiting");
    }
  }

  function renderProgress(pluginDone, mcpDone, serverState) {
    const done = (pluginDone ? 1 : 0) + (mcpDone ? 1 : 0);
    // Step 3 (Studio connect) we can't auto-detect — closest proxy is the
    // server being "running" (plugin actively polling would keep it busy, but
    // even idle bridge counts as healthy for setup purposes). We don't mark
    // it as automatically complete; user knows they did it when Claude works.
    const total = 3;
    const fill = $("progress-fill");
    if (fill) fill.style.width = `${(done / total) * 100}%`;
    $("progress-count").textContent = String(done);

    const badge = $("progress-badge");
    if (done === 0) {
      setBadge(badge, "danger", "Action required");
    } else if (done < 2) {
      setBadge(badge, "warning", "In progress");
    } else if (done === 2) {
      setBadge(badge, "info", "Almost there");
    } else {
      setBadge(badge, "success", "Ready");
    }

    const hint = $("next-hint");
    const ready = $("ready-card");
    if (!pluginDone) {
      hint.innerHTML = `<b>Next:</b> install the Studio plugin so Roblox Studio can talk to the bridge.`;
      if (ready) ready.classList.add("hidden");
    } else if (!mcpDone) {
      hint.innerHTML = `<b>Next:</b> register the bridge with Claude Code so the Roblox tools become available.`;
      if (ready) ready.classList.add("hidden");
    } else {
      hint.innerHTML = `<b>Final step:</b> open Roblox Studio and click <b>Connect</b> in the Claude Bridge toolbar.`;
      if (ready) ready.classList.remove("hidden");
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
    try {
      const state = await api.getState();
      const pluginDone = renderPlugin(state);
      const mcpDone = renderMcp(state);
      renderServer(state);
      renderStepper(pluginDone, mcpDone);
      renderProgress(pluginDone, mcpDone, state.status.server);
      renderSettings(state);
      return state;
    } catch (err) {
      console.error("[renderer] refresh failed:", err);
    }
  }

  async function withBusy(button, fn) {
    const orig = button.textContent;
    button.disabled = true;
    button.textContent = "Working…";
    try {
      await fn();
    } catch (err) {
      console.error("[renderer] action failed:", err);
      alert(err.message || String(err));
    } finally {
      button.disabled = false;
      button.textContent = orig;
      await refresh();
    }
  }

  function bindActions() {
    $("btn-install-plugin").addEventListener("click", (e) => {
      withBusy(e.currentTarget, () => api.installPlugin());
    });
    $("btn-open-plugins").addEventListener("click", () => api.openPluginsFolder());

    $("btn-register-mcp").addEventListener("click", (e) => {
      withBusy(e.currentTarget, () => api.registerMcp());
    });
    $("btn-open-config").addEventListener("click", () => api.openConfigFile());

    $("btn-toggle-server").addEventListener("click", (e) => {
      const action = e.currentTarget.dataset.action;
      withBusy(e.currentTarget, async () => {
        if (action === "stop") await api.stopServer();
        else await api.startServer();
        await new Promise((r) => setTimeout(r, 400));
      });
    });

    $("btn-copy-token").addEventListener("click", (e) => {
      navigator.clipboard.writeText($("input-token").value);
      const b = e.currentTarget;
      const orig = b.textContent;
      b.textContent = "Copied";
      setTimeout(() => { b.textContent = orig; }, 1200);
    });
    $("btn-regenerate-token").addEventListener("click", async (e) => {
      if (!confirm("Regenerate token? This reinstalls the plugin and updates Claude Code config.")) return;
      withBusy(e.currentTarget, () => api.regenerateToken());
    });

    $("btn-clear-logs").addEventListener("click", () => { $("log-view").textContent = ""; });
  }

  setTabs();
  bindActions();
  api.onLog((line) => appendLog(line));
  api.onServerExit((info) => {
    appendLog({ ts: Date.now(), line: `--- server exited (code=${info.code}) ---` });
    refresh();
  });

  refresh();
  setInterval(refresh, 4000);
})();
