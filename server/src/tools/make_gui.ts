import { z } from "zod";
import type { Queue } from "../queue.js";

const guiNodeSchema: z.ZodType<unknown> = z.lazy(() =>
  z.object({
    className: z
      .string()
      .describe('Roblox class, e.g. "ScreenGui", "Frame", "TextLabel", "ImageLabel", "UIListLayout"'),
    name: z.string().optional(),
    properties: z
      .record(z.unknown())
      .optional()
      .describe(
        "Property bag. Values may be primitives or {type:\"UDim2\",scaleX,offX,scaleY,offY}, {type:\"Color3\",r,g,b}, {type:\"Vector2\",x,y}, {type:\"UDim\",scale,offset}, {type:\"Enum\",enumType,name}",
      ),
    children: z.array(guiNodeSchema).optional(),
  }),
);

export const makeGuiSchema = z.object({
  parent: z
    .string()
    .default("game.StarterGui")
    .describe('Where to place the root, e.g. "game.StarterGui", "game.StarterGui.HUD"'),
  tree: guiNodeSchema.describe("Root node — typically a ScreenGui containing Frames/TextLabels/etc."),
  replaceExisting: z
    .boolean()
    .default(false)
    .describe("If true and a sibling with the same Name exists under parent, destroy it first"),
});

export type MakeGuiArgs = z.infer<typeof makeGuiSchema>;

export async function makeGui(queue: Queue, raw: unknown) {
  const args = makeGuiSchema.parse(raw);
  return queue.request("make_gui", args);
}
