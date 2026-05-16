import { randomUUID } from "node:crypto";

export type PendingRequest = {
  id: string;
  tool: string;
  args: unknown;
};

type Waiter = {
  resolve: (value: unknown) => void;
  reject: (err: Error) => void;
  timer: NodeJS.Timeout;
};

type Poller = {
  resolve: (req: PendingRequest | null) => void;
  timer: NodeJS.Timeout;
};

export class Queue {
  private pending: PendingRequest[] = [];
  private waiters = new Map<string, Waiter>();
  private pollers: Poller[] = [];

  // Called by MCP tools. Returns a promise that resolves when the plugin
  // posts a matching result, or rejects on timeout.
  request(tool: string, args: unknown, timeoutMs = 30_000): Promise<unknown> {
    const id = randomUUID();
    const req: PendingRequest = { id, tool, args };

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.waiters.delete(id);
        reject(new Error(`Timeout waiting for plugin response to "${tool}" (${timeoutMs}ms). Is the Studio plugin connected?`));
      }, timeoutMs);

      this.waiters.set(id, { resolve, reject, timer });

      // Hand off to a waiting poller if any
      const poller = this.pollers.shift();
      if (poller) {
        clearTimeout(poller.timer);
        poller.resolve(req);
      } else {
        this.pending.push(req);
      }
    });
  }

  // Called by HTTP bridge when plugin GETs /poll. Long-polls up to waitMs.
  poll(waitMs = 25_000): Promise<PendingRequest | null> {
    const next = this.pending.shift();
    if (next) return Promise.resolve(next);

    return new Promise((resolve) => {
      const timer = setTimeout(() => {
        const idx = this.pollers.findIndex((p) => p.resolve === resolve);
        if (idx >= 0) this.pollers.splice(idx, 1);
        resolve(null);
      }, waitMs);
      this.pollers.push({ resolve, timer });
    });
  }

  // Called by HTTP bridge when plugin POSTs /result.
  resolve(id: string, ok: boolean, payload: unknown): boolean {
    const waiter = this.waiters.get(id);
    if (!waiter) return false;
    clearTimeout(waiter.timer);
    this.waiters.delete(id);
    if (ok) waiter.resolve(payload);
    else waiter.reject(new Error(typeof payload === "string" ? payload : JSON.stringify(payload)));
    return true;
  }
}
