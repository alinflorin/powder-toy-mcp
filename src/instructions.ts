export const INSTRUCTIONS: string = `pt - control The Powder Toy (the game must be running with the plugin loaded)

USAGE
  pt execute "<command> [args...]"

Coordinates: x 0..611, y 0..383, origin top-left. Elements are given by name
(case-insensitive, e.g. DUST, WATR, FIRE) or numeric id. Run "elements" to list them.

SIMULATION
  play                       resume simulation
  pause                      pause simulation
  step [n]                   advance n frames (default 1; pauses first)
  clear                      clear all particles/walls/signs

DRAWING
  draw pixel  <elem> <x> <y>
  draw line   <elem> <x1> <y1> <x2> <y2> [rx ry]     (rx/ry = brush half-size, default 0 0)
  draw rect   <elem> <x1> <y1> <x2> <y2>             filled box
  draw circle <elem> <x> <y> <r>                     filled circle brush
  draw fill   <elem> <x> <y>                         flood fill the region at x,y
  draw wall   <wallname|id> <x1> <y1> <x2> <y2>      filled wall box (e.g. WALL, STREAM, ERASEALL)
  erase <x1> <y1> <x2> <y2>                          remove particles and walls in box

INSPECTION
  elements                   list element names/ids
  get element <elem>         properties of an element
  get particle <x> <y>       particle at position
  get area <x1> <y1> <x2> <y2>   particle counts per element in box (max 100000 cells)
  info                       project/stats: pause state, particle count, frame, env

ENVIRONMENT
  env                        show all settings
  env set <key> <value>
    gravity   vertical|off|radial     (or 0|1|2)
    air       on|pressure_off|velocity_off|off|no_update   (or 0..4)
    edge      void|solid|loop         (or 0..2)
    ambient   <kelvin>                ambient air temperature
    heat      on|off                  ambient heat simulation
    newtonian on|off                  newtonian gravity
  env reset pressure|temp            reset pressure map / particle temperatures

SCREEN
  screenshot [scale] [x1 y1 x2 y2]   PNG render of particles (scale 1..4, optional crop box)

ADVANCED
  lua <code>                 run Lua inside the game (sim, elem, tpt, ... available); return value is printed
  api [table]                list members of a Lua table (sim, elem, tpt, gfx, interface, event, socket) to verify API availability
  ping                       connectivity check
`;
