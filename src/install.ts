import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const MARKER = "Powder Toy MCP plugin";

export function gameDataDir(): string {
  const home = os.homedir();
  if (process.platform === "darwin") return path.join(home, "Library", "Application Support", "The Powder Toy");
  if (process.platform === "win32") return path.join(process.env.APPDATA ?? path.join(home, "AppData", "Roaming"), "The Powder Toy");
  return path.join(process.env.XDG_DATA_HOME ?? path.join(home, ".local", "share"), "The Powder Toy");
}

/** Copies the bundled plugin/autorun.lua into the game's data directory. */
export function installPlugin(args: string[]): number {
  const force = args.includes("--force");
  const dirArg = args.find((a) => !a.startsWith("--"));
  const dir = dirArg ?? gameDataDir();
  const src = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "plugin", "autorun.lua");
  const dest = path.join(dir, "autorun.lua");
  if (!fs.existsSync(src)) {
    console.error(`bundled plugin not found at ${src}`);
    return 1;
  }
  fs.mkdirSync(dir, { recursive: true });
  if (fs.existsSync(dest) && !force) {
    const existing = fs.readFileSync(dest, "utf8");
    if (!existing.includes(MARKER) && !fs.lstatSync(dest).isSymbolicLink()) {
      console.error(`${dest} exists and is not this plugin; re-run with --force to overwrite`);
      return 1;
    }
  }
  fs.rmSync(dest, { force: true }); // also replaces dev symlinks instead of writing through them
  fs.copyFileSync(src, dest);
  console.log(`installed plugin to ${dest}\nRestart Powder Toy to load it.`);
  return 0;
}
