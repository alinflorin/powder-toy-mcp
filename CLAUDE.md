# Powder Toy MCP

Exposes The Powder Toy game functions as an MCP server, styled as a fake CLI:

- `pt read_instructions` — returns usage docs for the available commands
- `pt execute` — runs a command against the running game

## Architecture

Two parts connected by IPC:

1. **Lua plugin** (runs inside Powder Toy): loaded via `autorun.lua` or the Script Manager. It uses the in-game Lua API (`sim`, `elem`, `gfx`, `event`, `interface`, legacy `tpt`) to execute commands and report results. It talks to the outside world through a TCP socket (fallback: a command/response file pair) and processes commands from an `event` tick hook so they run on the game thread.
2. **MCP server** (external Node.js process): exposes `read_instructions` and `execute` tools, translates calls into messages for the Lua plugin, and returns the responses (text or images) to the client.

## Environment findings

- OS: Arch-based (CachyOS), zsh/fish shell.
- Powder Toy: AUR/pacman package `powder-toy` 100.1.400-2, binary at `/usr/bin/powder-toy`, dynamically linked against `libluajit-5.1.so.2`.
- Lua inside the game is **LuaJIT 2.1 (Lua 5.1 semantics)**: use `bit.*` instead of bitwise operators, no integer division `//`, no `goto`-style 5.2+/5.3+ features.
- The binary contains built-in `socket` (with `TCPSocket`), `fileSystem`, and `bit` libraries (found via `strings`; not yet verified at runtime). Socket errors suggest TCP only, probably non-blocking and polled from a tick hook. Verify with `require("socket")` in the in-game console (`~`).
- Game data dir: `~/.local/share/The Powder Toy/` (contains `powder.pref`; put `autorun.lua` here).
- Standalone `lua` 5.5.1 and `luajit` 2.1 are installed on the host for testing pure-logic code only; they do not provide `sim`/`tpt`/`elem` APIs.
- MCP server language: **Node.js** (TypeScript or JS with the official `@modelcontextprotocol/sdk`).

## Transport decision

Plugin connects over TCP using the in-game `socket` library to the Node MCP server (no file-polling fallback needed unless the runtime check fails). Plugin code must be non-blocking and driven from an `event` tick hook.

## Required capabilities

- Draw elements on screen (particles, lines, rects, fill, walls)
- Play / pause the simulation (and step frames)
- Get info on objects (particle at a position, element properties, area queries)
- Get info on the project (save metadata, particle counts, frame, stats)
- Render the screen as PNG and return the image for inspection
- Change game environment settings (gravity, air, heat, ambient temperature, edge mode, etc.)

## Guidelines

- All simulation access must happen inside the Lua plugin, on the game thread (event hooks); never block the game loop.
- Keep the MCP surface small: `read_instructions` documents every command, `execute` takes a command string plus arguments.
- Return structured, concise errors (unknown element, out-of-bounds coordinates, game not connected).
- Verify Lua API availability against the installed Powder Toy version before relying on a function.
