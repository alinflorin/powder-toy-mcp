export const INSTRUCTIONS: string = `pt - control The Powder Toy (the game must be running with the plugin loaded)

USAGE
  pt execute "<command> [args...]"

TIPS
  - PREFERRED for anything repetitive or procedural (many shapes, grids, lattices, loops): use "lua <code>"
    instead of many single draw commands. One call can build a whole scene, e.g.
      lua for i=0,4 do sim.createBox(240+i*30, 220, 250+i*30, 340, elem.DEFAULT_PT_URAN) end
    Use "api sim" / "api elem" to see available functions. Use plain draw commands for one-off shapes.
  - Commands are processed in arrival order; do NOT fire dependent commands in parallel. Use "batch"
    or sequential calls. Pause and build walls before adding liquids/powders (the default edge is "void",
    so unwalled liquids fall off screen; "env set edge solid" keeps them in).
  - Plain particles are only created in empty cells; use --replace to overwrite. Draw solids before fluids.
  - Ambient heat is off by default: "env set heat on" for heat-driven setups.

Coordinates: x 0..611, y 0..383, origin top-left. Elements are given by name
(case-insensitive, e.g. DUST, WATR, FIRE) or numeric id. Run "elements" to list them.

SIMULATION
  play                       resume simulation
  pause                      pause simulation
  step [n]                   advance n frames (default 1; pauses first)
  clear                      clear all particles/walls/signs
  watch <frames> [every] [x1 y1 x2 y2]   step and print stats every N frames (particles, max temp/pressure, top elements)
  undo | redo | snapshot     history control (snapshot saves a restore point)
  batch <cmd> ; <cmd> ; ...  run several commands in order in one call (stops at first error)

DRAWING
  draw pixel  <elem> <x> <y>
  draw line   <elem> <x1> <y1> <x2> <y2> [rx ry]     (rx/ry = brush half-size, default 0 0)
  draw rect   <elem> <x1> <y1> <x2> <y2>             filled box
  draw circle <elem> <x> <y> <r>                     filled circle brush
  draw fill   <elem> <x> <y>                         flood fill the region at x,y
  draw hollow <elem> <x1> <y1> <x2> <y2> [thick]     rectangle outline
  draw wall   <wallname|id> <x1> <y1> <x2> <y2>      filled wall box (names: see "walls"; WALL=8)
  draw tank   <wallname|id> <x1> <y1> <x2> <y2> [thick]   walled container (default thickness 4); prints the inside box
  Add --replace to pixel/rect/circle to overwrite existing particles (otherwise occupied cells are skipped).
  erase [particles|walls] <x1> <y1> <x2> <y2>        remove particles and/or walls in box (default both)
  replace <from> <to> [x1 y1 x2 y2]                  change the element of matching particles
  set particle <x> <y> <prop> <value>                props: temp life ctype tmp tmp2 tmp3 tmp4 vx vy dcolour
  set area <x1> <y1> <x2> <y2> <prop> <value> [elem] set a property on many particles (temp in K or e.g. 25C)
  stamp save <x1> <y1> <x2> <y2> | stamp load <name> <x> <y> | stamp list

INSPECTION
  elements                   list element names/ids
  get element <elem>         properties of an element
  get particle <x> <y>       particle at position
  get area <x1> <y1> <x2> <y2>   per-element counts plus temperature and pressure stats in box
  get wall <x> <y>           wall type at position
  get cell <x> <y>           wall, pressure, air velocity, ambient temp of the 4x4 cell
  count [elem]               particle count (all or one element)
  find <elem> [x1 y1 x2 y2]  count, bounding box and sample positions of an element
  walls                      list wall names/ids
  info                       project/stats: pause state, particle count, temp/pressure, env

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
  screenshot [scale] [x1 y1 x2 y2]   PNG render of particles and walls (scale 1..4, optional crop box)

ADVANCED
  lua <code>                 run Lua inside the game (sim, elem, tpt, ... available); return value is printed
  api [table]                list members of a Lua table (sim, elem, tpt, gfx, interface, event, socket) to verify API availability
  ping                       connectivity check
`;
