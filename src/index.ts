#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { Bridge } from "./bridge.js";
import { INSTRUCTIONS } from "./instructions.js";
import { installPlugin } from "./install.js";

if (process.argv[2] === "install-plugin") process.exit(installPlugin(process.argv.slice(3)));

const log = (m: string) => process.stderr.write(`[pt] ${m}\n`);
const bridge = new Bridge({ port: Number(process.env.PT_PORT) || 8787, log });
await bridge.listen();

const server = new McpServer({ name: "pt", version: "0.1.0" });

server.tool("read_instructions", "pt read_instructions: usage docs for every pt command", async () => ({
  content: [{ type: "text" as const, text: INSTRUCTIONS }],
}));

server.tool(
  "execute",
  "pt execute: run a command against the running Powder Toy game. Call read_instructions first for the command list.",
  { command: z.string().describe('Command line, e.g. "draw line DUST 10 10 200 10"') },
  async ({ command }) => {
    const cmd = command.trim().replace(/^pt\s+(execute\s+)?/, "");
    if (!cmd) return { isError: true, content: [{ type: "text" as const, text: "error: empty command; see read_instructions" }] };
    try {
      const r = await bridge.send(cmd);
      if (r.kind === "png") {
        return { content: [{ type: "image" as const, data: (r.data as Buffer).toString("base64"), mimeType: "image/png" }] };
      }
      return { isError: !r.ok, content: [{ type: "text" as const, text: r.ok ? String(r.data) : `error: ${r.data}` }] };
    } catch (e) {
      return { isError: true, content: [{ type: "text" as const, text: `error: ${(e as Error).message}` }] };
    }
  }
);

await server.connect(new StdioServerTransport());
log("MCP server ready");
