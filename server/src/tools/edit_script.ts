import { z } from "zod";
import type { Queue } from "../queue.js";

export const editScriptSchema = z.object({
  path: z
    .string()
    .describe('DataModel path to a Script/LocalScript/ModuleScript, e.g. "game.ServerScriptService.MainServer"'),
  source: z.string().describe("Full new source for the script (replaces existing contents)"),
  createIfMissing: z
    .boolean()
    .default(false)
    .describe("If true and the final node does not exist, create it"),
  className: z
    .enum(["Script", "LocalScript", "ModuleScript"])
    .default("ModuleScript")
    .describe("Class to create when createIfMissing is true"),
});

export type EditScriptArgs = z.infer<typeof editScriptSchema>;

export async function editScript(queue: Queue, raw: unknown) {
  const args = editScriptSchema.parse(raw);
  return queue.request("edit_script", args);
}
