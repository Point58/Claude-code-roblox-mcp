import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { Queue } from "./queue.js";

function readBody(req: IncomingMessage, max = 4 * 1024 * 1024): Promise<string> {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks: Buffer[] = [];
    req.on("data", (c: Buffer) => {
      size += c.length;
      if (size > max) {
        reject(new Error("payload too large"));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

function json(res: ServerResponse, status: number, body: unknown) {
  const text = JSON.stringify(body);
  res.writeHead(status, {
    "content-type": "application/json",
    "content-length": Buffer.byteLength(text),
  });
  res.end(text);
}

export type BridgeOptions = {
  host: string;
  port: number;
  token: string;
  queue: Queue;
  log: (msg: string) => void;
};

export function startBridge(opts: BridgeOptions) {
  const { host, port, token, queue, log } = opts;

  const server = createServer(async (req, res) => {
    try {
      const url = new URL(req.url ?? "/", `http://${host}:${port}`);
      const auth = req.headers["authorization"];
      const expected = `Bearer ${token}`;
      if (auth !== expected) {
        return json(res, 401, { error: "unauthorized" });
      }

      if (req.method === "GET" && url.pathname === "/poll") {
        const next = await queue.poll();
        return json(res, 200, next ?? { idle: true });
      }

      if (req.method === "POST" && url.pathname === "/result") {
        const body = await readBody(req);
        const parsed = JSON.parse(body) as { id?: string; ok?: boolean; data?: unknown };
        if (!parsed.id || typeof parsed.ok !== "boolean") {
          return json(res, 400, { error: "missing id or ok" });
        }
        const found = queue.resolve(parsed.id, parsed.ok, parsed.data);
        return json(res, 200, { acknowledged: found });
      }

      if (req.method === "GET" && url.pathname === "/health") {
        return json(res, 200, { ok: true });
      }

      return json(res, 404, { error: "not found" });
    } catch (err) {
      log(`bridge error: ${(err as Error).message}`);
      return json(res, 500, { error: (err as Error).message });
    }
  });

  server.listen(port, host, () => {
    log(`bridge listening on http://${host}:${port}`);
  });

  return server;
}
