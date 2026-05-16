import { z } from "zod";
import type { Queue } from "../queue.js";

export const inspectSchema = z.object({
  path: z
    .string()
    .default("game")
    .describe('DataModel path like "game", "game.Workspace", or "game.StarterGui.MyGui"'),
  maxDepth: z.number().int().min(1).max(10).default(3).describe("How deep to walk the tree"),
  includeProperties: z
    .boolean()
    .default(false)
    .describe("If true, include common properties (Name, ClassName, plus a few class-specific)"),
});

export type InspectArgs = z.infer<typeof inspectSchema>;

export async function inspect(queue: Queue, raw: unknown) {
  const args = inspectSchema.parse(raw);
  return queue.request("inspect", args);
}
