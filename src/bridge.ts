import { pngFromRgbPayload } from "./png.js";
import net from "node:net";

export interface BridgeOptions {
  port?: number;
  host?: string;
  timeoutMs?: number;
  log?: (msg: string) => void;
}

export interface BridgeResult {
  ok: boolean;
  kind: "text" | "png";
  data: string | Buffer;
}

interface Pending {
  resolve: (r: BridgeResult) => void;
  reject: (e: Error) => void;
  timer: NodeJS.Timeout;
}

/**
 * TCP bridge. The server listens; the in-game Lua plugin connects.
 * Protocol (newline-delimited):
 *   server -> plugin: "<id> <command string>\n"
 *   plugin -> server: "<id> <ok|err> <text|png|rgb> <base64 payload>  (rgb = raw pixels, see png.ts)\n"
 */
export class Bridge {
  readonly port: number;
  readonly host: string;
  private readonly timeoutMs: number;
  private readonly log: (msg: string) => void;
  private sock: net.Socket | null = null;
  private nextId = 1;
  private readonly pending = new Map<number, Pending>();
  private readonly server: net.Server;

  constructor({ port = 8787, host = "127.0.0.1", timeoutMs = 20000, log = () => {} }: BridgeOptions = {}) {
    this.port = port;
    this.host = host;
    this.timeoutMs = timeoutMs;
    this.log = log;
    this.server = net.createServer((s) => this.#onConnect(s));
  }

  listen(): Promise<void> {
    return new Promise((resolve, reject) => {
      this.server.once("error", reject);
      this.server.listen(this.port, this.host, () => {
        this.server.off("error", reject);
        this.log(`bridge listening on ${this.host}:${this.port}`);
        resolve();
      });
    });
  }

  close(): void {
    this.sock?.destroy();
    this.server.close();
  }

  get connected(): boolean {
    return !!this.sock;
  }

  #onConnect(s: net.Socket) {
    if (this.sock) this.sock.destroy();
    this.sock = s;
    this.log("plugin connected");
    let buf = "";
    s.setEncoding("utf8");
    s.on("data", (d) => {
      buf += d;
      let i: number;
      while ((i = buf.indexOf("\n")) >= 0) {
        const line = buf.slice(0, i).replace(/\r$/, "");
        buf = buf.slice(i + 1);
        if (line) this.#onLine(line);
      }
    });
    const drop = () => {
      if (this.sock !== s) return;
      this.sock = null;
      this.log("plugin disconnected");
      for (const [id, p] of this.pending) {
        clearTimeout(p.timer);
        p.reject(new Error("game disconnected"));
        this.pending.delete(id);
      }
    };
    s.on("close", drop);
    s.on("error", drop);
  }

  #onLine(line: string) {
    const m = /^(\d+) (ok|err) (text|png|rgb) ?(.*)$/.exec(line);
    if (!m) return this.log(`bad line from plugin: ${line.slice(0, 80)}`);
    const p = this.pending.get(Number(m[1]));
    if (!p) return;
    this.pending.delete(Number(m[1]));
    clearTimeout(p.timer);
    const payload = Buffer.from(m[4], "base64");
    const ok = m[2] === "ok";
    if (m[3] === "rgb") {
      try {
        return p.resolve({ ok, kind: "png", data: pngFromRgbPayload(payload) });
      } catch (e) {
        return p.reject(new Error(`bad screenshot payload: ${(e as Error).message}`));
      }
    }
    p.resolve({ ok, kind: m[3] as "text" | "png", data: m[3] === "png" ? payload : payload.toString("utf8") });
  }

  send(command: string): Promise<BridgeResult> {
    if (!this.sock) {
      return Promise.reject(
        new Error(`game not connected (plugin should connect to ${this.host}:${this.port}; is Powder Toy running with autorun.lua?)`)
      );
    }
    const id = this.nextId++;
    return new Promise<BridgeResult>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`timeout after ${this.timeoutMs}ms waiting for game`));
      }, this.timeoutMs);
      this.pending.set(id, { resolve, reject, timer });
      this.sock!.write(`${id} ${command.replace(/[\r\n]+/g, " ")}\n`);
    });
  }
}
