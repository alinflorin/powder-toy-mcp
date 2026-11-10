# Powder Toy MCP

An [MCP](https://modelcontextprotocol.io) server that lets an AI client control [The Powder Toy](https://powdertoy.co.uk/) through a small, CLI-style tool surface.

> **Status:** early stage. The design is settled; the implementation is not written yet.

## How it works

```
MCP client ──stdio──> Node.js MCP server ──TCP──> Lua plugin (inside Powder Toy)
```

- **Lua plugin** — runs inside the game (loaded via `autorun.lua`), uses the in-game Lua API (`sim`, `elem`, `gfx`, `event`) and executes commands on the game thread from a tick hook.
- **MCP server** — a Node.js process exposing two tools, which forward commands to the plugin and return the results (text or images).

## Tools

| Tool | Description |
| --- | --- |
| `pt read_instructions` | Returns usage docs for all available commands |
| `pt execute` | Runs a command against the running game |

## Planned capabilities

- Draw elements on screen (particles, lines, rectangles, fill, walls)
- Play / pause the simulation, step frames
- Get info on objects (particles, elements, areas)
- Get info on the project (save metadata, particle counts, frame)
- Render the screen as PNG and return it for inspection
- Change environment settings (gravity, air, heat, ambient temperature, edge mode, …)

## Requirements

- The Powder Toy 100.x (tested target: `powder-toy` 100.1.400 from the AUR), which embeds LuaJIT 2.1 (Lua 5.1 semantics) and a `socket` library
- Node.js and npm
- Optional: standalone `lua` / `luajit` for testing pure-logic code outside the game

## Installation

Not available yet. The plan is:

1. Install dependencies for the MCP server (`npm install`).
2. Copy or symlink the plugin's `autorun.lua` into the game's data folder (`~/.local/share/The Powder Toy/` on Linux).
3. Register the MCP server with your client.

## Notes

- Plugin code must stay compatible with LuaJIT / Lua 5.1 (use `bit.*` rather than bitwise operators).
- All simulation access happens in the plugin, on the game thread, and must never block the game loop.
- Socket availability was found by inspecting the game binary and still needs a runtime check (`require("socket")` in the in-game console, opened with `~`).

See [CLAUDE.md](CLAUDE.md) for the full design notes and environment findings.
