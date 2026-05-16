import { z } from "zod";
import type { Queue } from "../queue.js";

export const runCodeSchema = z.object({
  code: z.string().describe("Luau source to execute inside Studio (plugin context, has full access)"),
  timeoutMs: z.number().int().min(100).max(60_000).default(5_000),
});

export type RunCodeArgs = z.infer<typeof runCodeSchema>;

export async function runCode(queue: Queue, raw: unknown) {
  const args = runCodeSchema.parse(raw);
  return queue.request("run_code", args, args.timeoutMs + 5_000);
}
