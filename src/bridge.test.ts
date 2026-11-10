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

test("converts rgb screenshot payloads to scaled PNGs", async () => {
  const { pngFromRgbPayload } = await import("./png.js");
  const header = Buffer.from([0, 2, 0, 2, 2]); // 2x2, scale 2
  const rgb = Buffer.from([255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255]);
  const png = pngFromRgbPayload(Buffer.concat([header, rgb]));
  assert.equal(png.subarray(1, 4).toString(), "PNG");
  assert.equal(png.readUInt32BE(16), 4); // width
  assert.equal(png.readUInt32BE(20), 4); // height

  const b = new Bridge({ port: PORT + 2 });
  await b.listen();
  const s = net.connect(PORT + 2, "127.0.0.1");
  s.on("data", (d) => s.write(`${d.toString().split(" ")[0]} ok rgb ${Buffer.concat([header, rgb]).toString("base64")}\n`));
  await new Promise((r) => s.once("connect", r));
  await new Promise((r) => setTimeout(r, 50));
  const r = await b.send("screenshot");
  assert.equal(r.kind, "png");
  assert.equal((r.data as Buffer).readUInt32BE(16), 4);
  s.destroy();
  b.close();
});
