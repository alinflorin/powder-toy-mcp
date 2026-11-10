import { test } from "node:test";
import assert from "node:assert/strict";
import net from "node:net";
import { Bridge } from "./bridge.js";

const PORT = 18787;

test("rejects when no plugin is connected", async () => {
  const b = new Bridge({ port: PORT });
  await b.listen();
  await assert.rejects(b.send("ping"), /game not connected/);
  b.close();
});

test("round-trips text and png replies", async () => {
  const b = new Bridge({ port: PORT + 1 });
  await b.listen();
  const s = net.connect(PORT + 1, "127.0.0.1");
  s.on("data", (d) => {
    const [id, cmd] = d.toString().trim().split(" ");
    const kind = cmd === "screenshot" ? "png" : "text";
    s.write(`${id} ok ${kind} ${Buffer.from("hello").toString("base64")}\n`);
  });
  await new Promise((r) => s.once("connect", r));
  await new Promise((r) => setTimeout(r, 50));
  assert.deepEqual(await b.send("ping"), { ok: true, kind: "text", data: "hello" });
  const png = await b.send("screenshot");
  assert.equal(png.kind, "png");
  assert.ok(Buffer.isBuffer(png.data));
  s.destroy();
  b.close();
});
