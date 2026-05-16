# Claude Roblox Bridge

Code your Roblox game by talking to Claude.

This is an open-source bridge between **Claude Code** and **Roblox Studio**. Claude can read your DataModel, edit scripts, build HUDs, and run Luau live in Studio — you just describe what you want in plain language.

The Bridge ships as a single Windows installer. No terminal, no Node, no token wrangling.

---

## For end users (download & go)

1. Grab **`Claude Roblox Bridge-Setup-X.Y.Z.exe`** from the [Releases](../../releases) page and run it.
2. Launch **Claude Roblox Bridge** from the Start menu. You'll see three cards on the dashboard:
   - **Studio plugin** — click **Install plugin**. The plugin is dropped into your Roblox Plugins folder with a token already embedded.
   - **Claude Code MCP** — click **Register with Claude Code**. This wires the Bridge into Claude Code.
   - **Bridge server** — leave it on "Will start when Claude Code launches" (default), or click **Start server** to test now.
3. Open Roblox Studio and any place. In the **Plugins** tab you'll see a **Claude Bridge** toolbar. Click **Connect**.
4. Open Claude Code in any terminal. Say something like:
   > *Build me a HUD with a health bar in the top-left*

That's it. Claude Code calls the Roblox tools automatically — you never pick them yourself.

### Prerequisites

- Windows 10 / 11 (x64)
- [Roblox Studio](https://create.roblox.com/) installed
- [Claude Code](https://claude.com/claude-code) installed

---

## What Claude can do

### Read
| Tool                  | What it does                                                                 |
| --------------------- | ---------------------------------------------------------------------------- |
| `roblox_inspect`      | Walk DataModel from a path, return tree (names, classes, optional properties)|
| `roblox_search`       | Find Instances by name pattern and/or class under a root                     |
| `roblox_get_selection`| Return what the user has selected in Studio                                  |
| `roblox_get_properties`| Read properties of an Instance (curated or specific list)                   |
| `roblox_read_script`  | Read the `Source` of a Script / LocalScript / ModuleScript                   |

### Execute
| Tool                  | What it does                                                                 |
| --------------------- | ---------------------------------------------------------------------------- |
| `roblox_run_code`     | Execute Luau in Studio and capture Output + return value                     |

### Write
| Tool                    | What it does                                                                |
| ----------------------- | --------------------------------------------------------------------------- |
| `roblox_edit_script`    | Replace the `Source` of a Script / LocalScript / ModuleScript               |
| `roblox_create_instance`| Create any Instance (Part, Folder, RemoteEvent, Sound, ...) with properties |
| `roblox_make_gui`       | Build a GUI tree under e.g. StarterGui                                      |
| `roblox_set_properties` | Apply property bag to an existing Instance                                  |
| `roblox_select`         | Select Instance(s) in Studio (visual confirmation)                          |
| `roblox_delete`         | Destroy Instance(s) at the given paths                                      |
| `roblox_undo`           | Undo recent bridge-recorded changes via ChangeHistoryService                |

All write operations record into `ChangeHistoryService`, so the user can Ctrl+Z them like any other Studio change. You don't pick these — Claude does, based on what you ask.

---

## How it works

```
Claude Code  <──stdio (MCP)──>  Bridge server (Bun-compiled exe)  <──HTTP long-poll──>  Studio plugin (Luau)
```

- **Bridge server**: a single ~50 MB binary (server/src compiled with `bun build --compile`). It exposes 4 MCP tools to Claude Code over stdio, and an HTTP endpoint on `127.0.0.1:31416` that the Studio plugin polls.
- **Studio plugin**: a single `.lua` file installed into `%LOCALAPPDATA%\Roblox\Plugins\`. Polls the bridge for jobs, executes them in Studio, posts results back.
- **Desktop manager (this app)**: an Electron app. Owns the install, manages the token, registers the MCP server with Claude Code, shows status. Not required to be running for Claude/Studio to work after first-time setup — the server is spawned by Claude Code on demand.

---

## For developers (build from source)

```bash
git clone <repo>
cd claude-roblox-mcp

# build server (TypeScript -> dist/)
cd server && bun install && bun run build && cd ..

# OR compile to standalone exe
cd server && bun build --compile --target=bun-windows-x64 ./src/index.ts --outfile ../app/resources/claude-roblox-mcp.exe && cd ..

# run the manager app in dev mode
cd app && npm install && npm start
```

### Manual setup (no GUI app)

If you'd rather skip the manager app:

```bash
# 1. Build server
cd server && bun install && bun run build

# 2. Register MCP
claude mcp add roblox \
  --env CLAUDE_ROBLOX_TOKEN="$(openssl rand -hex 16)" \
  -- node "$PWD/dist/index.js"

# 3. Install plugin
cp ../plugin-bundled/ClaudeBridge.server.luau \
   "$LOCALAPPDATA/Roblox/Plugins/ClaudeBridge.lua"
```

Then open Studio, click **Config** in the Claude Bridge toolbar, paste the same token, **Connect**.

### Releasing

Tag a commit with `v0.X.Y` and push. The GitHub Actions release workflow:

1. Spins up a Windows runner.
2. Installs Bun and Node.
3. Compiles `server/src/index.ts` → `app/resources/claude-roblox-mcp.exe`.
4. Runs `electron-builder` to produce the NSIS installer.
5. Uploads the installer to a fresh GitHub Release.

---

## Security notes

- The bridge HTTP server binds to `127.0.0.1` only — not reachable over the network.
- The shared token is stored in `%APPDATA%\claude-roblox-bridge\config.json`, embedded into the plugin file, and referenced from `~/.claude.json`. Regenerating from the Settings tab rotates all three.
- `roblox_run_code` executes arbitrary Luau in the Studio plugin's privileged context. Only install this bridge when you actually want Claude to drive Studio.

---

## License

MIT — see [LICENSE](./LICENSE).
