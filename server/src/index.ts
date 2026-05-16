#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { zodToJsonSchema } from "zod-to-json-schema";
import { Queue } from "./queue.js";
import { startBridge } from "./bridge.js";
import { inspect, inspectSchema } from "./tools/inspect.js";
import { runCode, runCodeSchema } from "./tools/run_code.js";
import { editScript, editScriptSchema } from "./tools/edit_script.js";
import { makeGui, makeGuiSchema } from "./tools/make_gui.js";
import type { ZodTypeAny } from "zod";

const log = (msg: string) => process.stderr.write(`[claude-roblox-mcp] ${msg}\n`);

const token = process.env.CLAUDE_ROBLOX_TOKEN;
if (!token) {
  log("ERROR: CLAUDE_ROBLOX_TOKEN env var is required (shared secret between server and Studio plugin)");
  process.exit(1);
}

const host = process.env.CLAUDE_ROBLOX_HOST ?? "127.0.0.1";
const port = Number(process.env.CLAUDE_ROBLOX_PORT ?? 31416);

const queue = new Queue();
startBridge({ host, port, token, queue, log });

type ToolDef = {
  name: string;
  description: string;
  schema: ZodTypeAny;
  handler: (queue: Queue, args: unknown) => Promise<unknown>;
};

const tools: ToolDef[] = [
  {
    name: "roblox_inspect",
    description:
      "Walk the Roblox DataModel from a given path and return its tree (names, classes, optionally properties). Use this first to understand the place's structure.",
    schema: inspectSchema,
    handler: inspect,
  },
  {
    name: "roblox_run_code",
    description:
      "Execute Luau code inside Roblox Studio (plugin context — full access). Captures Output and prints between start/end and returns them along with any return value. Use for one-off inspections, quick prototypes, or scripted edits.",
    schema: runCodeSchema,
    handler: runCode,
  },
  {
    name: "roblox_edit_script",
    description:
      "Replace the Source of a Script, LocalScript or ModuleScript at the given DataModel path. Optionally creates it if missing.",
    schema: editScriptSchema,
    handler: editScript,
  },
  {
    name: "roblox_make_gui",
    description:
      "Create a GUI tree (ScreenGui, Frames, TextLabels, etc.) under a parent like game.StarterGui. Use for HUDs, menus, overlays. Supports UDim2/Color3/Vector2/UDim/Enum typed values via {type:..., ...} objects.",
    schema: makeGuiSchema,
    handler: makeGui,
  },
];

const server = new Server(
  { name: "claude-roblox-mcp", version: "0.1.0" },
  { capabilities: { tools: {} } },
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: tools.map((t) => ({
    name: t.name,
    description: t.description,
    inputSchema: zodToJsonSchema(t.schema, { target: "openApi3" }) as Record<string, unknown>,
  })),
}));

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  const tool = tools.find((t) => t.name === req.params.name);
  if (!tool) {
    return {
      isError: true,
      content: [{ type: "text", text: `Unknown tool: ${req.params.name}` }],
    };
  }
  try {
    const result = await tool.handler(queue, req.params.arguments ?? {});
    return {
      content: [
        { type: "text", text: typeof result === "string" ? result : JSON.stringify(result, null, 2) },
      ],
    };
  } catch (err) {
    return {
      isError: true,
      content: [{ type: "text", text: (err as Error).message }],
    };
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
log("MCP server ready on stdio");
