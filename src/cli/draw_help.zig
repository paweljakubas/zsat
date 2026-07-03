const std = @import("std");

/// Help text for `zsat draw vec2d --help`
pub const vec2d_help =
    \\Vector data is the primary input format for `zsat draw`.
    \\
    \\Input shape:
    \\  stdin delivers one or more data rows, separated by newlines.
    \\  Each row is a comma-separated list of vector elements enclosed in [[...]].
    \\
    \\  [[x1,y1], [x2,y2], ...]   -- multi-segment vector (one object)
    \\  [[x1,y1]], [[x2,y2]]       -- two independent vectors (gathered, same style)
    \\  [[x1,y1]]\n[[x2,y2]]      -- two separate data rows (different styles possible)
    \\
    \\Coordinate systems:
    \\  xy     -- values are (x, y) in Cartesian space
    \\  polar  -- values are (r, phi) where phi is in degrees or radians
    \\
    \\Vector elements in a single row compose sequentially:
    \\  the second element starts where the first ends, and so on.
    \\  This forms a polyline that is treated as a single object:
    \\  it adopts one style and undergoes transformations as a whole.
    \\
    \\Every vector must be anchored in space before it can be drawn.
    \\  Use `anchor POINT` in the --outputs expression to pin the vector.
    \\  See `zsat draw point --help` for how to specify POINT.
    \\
    \\Vectors can also be transformed (rotated, scaled, mirrored) before anchoring.
    \\  Use `&` to compose operations: `(op2 & op1) out` means op2(op1(out)).
    \\  See `zsat draw vec2d output --help` for the available operations.
    \\
    \\Examples:
    \\  echo '[[1,1]]' | zsat draw
    \\  echo '[[1,1],[-1,0]]' | zsat draw
    \\  printf '[[1,1]]\n[[0,1]]' | zsat draw -s 'e0:{vec2d}, e1:{[lc:red]}' \\
    \\    -d '(v0,v1) -> (v0 -> e0, v1 -> e1)' \\
    \\    -o '(o0,o1) -> ((a {(0,0)}) o0, (a {(0,0)}) o1)'
;

/// Help text for `zsat draw vec2d style --help`
pub const vec2d_style_help =
    \\Style definition syntax:
    \\  eN:{TYPE ORIENTATION STEPS [ATTRIBUTES]}
    \\
    \\  eN     -- style key (e0, e1, ...) used for referencing in --datum
    \\  {...}  -- style body; all fields are optional and inherit from defaults
    \\
    \\TYPE (default: vec2d):
    \\  vec2d  -- input is parsed as 2D vectors
    \\
    \\COORDINATE SYSTEM (default: xy):
    \\  xy     -- values are (x, y) Cartesian coordinates
    \\  polar  -- values are (r, phi) where phi is an angle
    \\
    \\ORIENTATION (default: fixed):
    \\  fixed   -- each segment is defined in global coordinates
    \\  origin  -- each segment's origin is the end of the previous segment
    \\  coord   -- like origin, but the x-axis also aligns with the previous segment
    \\
    \\STEPS (default: last):
    \\  last  -- plot only the final result after all transformations
    \\  all   -- plot every intermediate step of composed transformations
    \\
    \\ATTRIBUTES inside [...]:
    \\  lw:N  -- line width in pixels (default: 10)
    \\  lc:NAME  -- line color, any CSS color name (default: black)
    \\  lo:N  -- line opacity, 0..100 (default: 100)
    \\  le:MODE  -- line ending: none | butt | round | square (default: none)
    \\  lj:MODE  -- line join: none | miter | round | bevel (default: none)
    \\  ld:[D1,O1,D2,O2,...] OFFSET  -- dashing pattern and offset in pixels
    \\
    \\Style inheritance:
    \\  e1: e0{[lc: red]}     -- e1 copies e0, then overrides lc to red
    \\  e2: e1{[ld: [10,5] 0]}  -- e2 copies e1, then adds dashing
    \\
    \\Examples:
    \\  e0:{vec2d xy fixed last [lw:15, lc: aqua]}
    \\  e0:{vec2d polar origin all [lw:5, lc: red, ld: [40,10] 0]}
;

/// Help text for `zsat draw vec2d output --help`
pub const vec2d_output_help =
    \\The --outputs expression defines how each data row is transformed and anchored.
    \\
    \\Syntax:
    \\  (out0, out1, ...) -> (EXPR0, EXPR1, ...)
    \\
    \\Each EXPR is a composition of operations applied right-to-left:
    \\  (op3 & op2 & op1) out   means   op3( op2( op1( out ) ) )
    \\
    \\Available operations:
    \\
    \\  anchor POINT      -- mandatory; pins the vector at the given point
    \\  rotate ANGLE around POINT  -- rotate counter-clockwise by ANGLE degrees
    \\  scale [SX,SY]     -- scale x and y components independently
    \\  mirror (LINE)     -- reflect across LINE
    \\  project TARGET    -- project onto a line or another output's direction
    \\  orthogonal TARGET -- orthogonal component relative to a line or output
    \\
    \\Shorthand forms:
    \\  a   -- anchor
    \\  r   -- rotate
    \\  s   -- scale
    \\  m   -- mirror
    \\  p   -- project
    \\  o   -- orthogonal
    \\
    \\ANGLE syntax:
    \\  90        -- 90 degrees
    \\  -45       -- negative 45 degrees (clockwise)
    \\  1r4p      -- pi/4  = 45 degrees
    \\  -1r6p     -- -pi/6 = -30 degrees
    \\  p         -- pi    = 180 degrees
    \\
    \\POINT syntax:  see `zsat draw point --help`
    \\LINE syntax:   see `zsat draw line --help`
    \\
    \\TARGET for project / orthogonal:
    \\  (LINE)            -- a line, e.g. (y=0) or (y=2x+1)
    \\  outN              -- reference to another output's direction
    \\  POINT             -- explicit point; produces a UNIT vector anchored there
    \\
    \\When TARGET is another output (e.g. `out2`):
    \\  - `p out2` projects the current vector onto out2's line
    \\  - `o out2` gives the orthogonal component; it starts where projection ends
    \\  - projection + orthogonal = original vector (as vectors)
    \\
    \\When TARGET is a POINT (e.g. `{(1,1)}` or `(beg out2)`):
    \\  - `p POINT` produces a unit vector parallel to the current output
    \\  - `o POINT` produces a unit vector 90 degrees CCW from the current output
    \\  - both are anchored at the resolved POINT
    \\
    \\Examples:
    \\  (out) -> (a {(0,0)}) out
    \\  (out) -> (r [90 a (0% self)] & a {(0,0)}) out
    \\  (out) -> (m (y=x) & a {(0,0)}) out
    \\  (out) -> (s [[2,1]] & a {(0,0)}) out
    \\  (out) -> (r [45 a (mid self)] & s [[1,2]] & a {(0,0)}) out
    \\  (out) -> (p out2 & a {(1,1)}) out        -- project onto out2's line
    \\  (out) -> (o out2 & a {(1,1)}) out        -- orthogonal to out2's direction
    \\  (out) -> (p (beg out2) & a {(1,1)}) out  -- unit vector anchored at out2's start
;

/// Help text for `zsat draw point --help`
pub const point_help =
    \\Points are used inside transformations (rotate, anchor, scale) to specify
    \\locations in space. A point can be given explicitly or by reference.
    \\
    \\Explicit point:
    \\  {(X, Y)}     -- absolute coordinates, e.g. {(0,0)} or {(1.5, -2)}
    \\
    \\Self-reference (referring to the object being transformed):
    \\  (beg self)       -- beginning of the current polyline
    \\  (mid self)       -- midpoint of the current polyline
    \\  (end self)       -- end of the current polyline
    \\  (0% self)        -- same as beg
    \\  (50% self)       -- same as mid
    \\  (100% self)      -- same as end
    \\  (-25% self)      -- 25% before the beginning
    \\  (125% self)      -- 25% past the end
    \\
    \\Cross-reference (referring to another output):
    \\  (beg out0)       -- beginning of output out0
    \\  (mid out1)       -- midpoint of output out1
    \\  (25% out0)       -- quarter-way along out0
    \\
    \\The `self` keyword refers to the result of the immediately preceding
    \\operation in the composition chain. `beg`, `mid`, and `end` are aliases
    \\for 0%, 50%, and 100% respectively.
    \\
    \\Examples:
    \\  rotate [90 a (0% self)]     -- rotate around the start of the vector
    \\  rotate [45 a (mid self)]    -- rotate around its midpoint
    \\  anchor (end out0)           -- anchor at the end of another output
;

/// Help text for `zsat draw line --help`
pub const line_help =
    \\Lines are used as the axis of reflection in the `mirror` transformation.
    \\
    \\Syntax:
    \\  (y = MX + B)    -- general line with slope M and intercept B
    \\  (y = C)         -- horizontal line
    \\  (x = C)         -- vertical line
    \\
    \\Special convenient forms:
    \\  (y = x)         -- diagonal through the origin (slope 1)
    \\  (y = -x)        -- diagonal through the origin (slope -1)
    \\  (x = 0)         -- the y-axis
    \\  (y = 0)         -- the x-axis
    \\
    \\The line is interpreted in the current coordinate system. In `fixed`
    \\mode this is the global system; in `origin` or `coord` mode it is
    \\the local system attached to the end of the previous step.
    \\
    \\Examples:
    \\  m (y = x)               -- mirror across the line y = x
    \\  m (x = 0.5)             -- mirror across the vertical line x = 0.5
    \\  m (y = 1) & m (x = 0.5) -- two successive mirrors
;

/// Help text for `zsat draw color --help`
pub const color_help =
    \\Colors are specified by name in the `lc` (line color) attribute.
    \\
    \\Any standard CSS color name is accepted. Common choices include:
    \\
    \\  black, white, grey, silver
    \\  red, green, blue, yellow, cyan, magenta
    \\  orange, purple, brown, pink
    \\  aqua, teal, navy, lime, olive
    \\  coral, salmon, tomato, gold, coral
    \\  lightblue, lightgreen, lightgrey, lightcoral
    \\  darkred, darkgreen, darkblue, darkgrey
    \\  aliceblue, antiquewhite, azure, beige, bisque
    \\  ... and many more (full CSS palette supported)
    \\
    \\Examples:
    \\  lc: black
    \\  lc: aqua
    \\  lc: lightcoral
    \\  lc: rebeccapurple
;

/// Help text for `zsat draw angle --help`
pub const angle_help =
    \\Angles are used in transformations like `rotate` and in polar coordinates.
    \\They can be expressed in degrees, in radians, or as fractions of pi.
    \\
    \\Degrees (default):
    \\  90        -- 90 degrees counter-clockwise
    \\  -45       -- 45 degrees clockwise
    \\  180       -- half turn
    \\
    \\Radians using `p` for pi:
    \\  p         -- pi radians = 180 degrees
    \\  2p        -- 2*pi radians = 360 degrees
    \\  -1r2p     -- -pi/2 = -90 degrees
    \\  1r4p      -- pi/4 = 45 degrees
    \\  -1r6p     -- -pi/6 = -30 degrees
    \\
    \\Fraction syntax:
    \\  NUMrDENp  -- means (NUM/DEN) * pi
    \\  The `r` stands for ratio. This avoids writing decimals like 0.3333.
    \\
    \\Examples:
    \\  rotate [90 a (0% self)]           -- rotate 90 degrees
    \\  rotate [1r4p a (mid self)]        -- rotate 45 degrees (pi/4)
    \\  rotate [-1r6p a (end self)]       -- rotate -30 degrees (-pi/6)
    \\  r [2p a (beg self)]               -- full 360-degree rotation
;

/// Help text for `zsat draw objects --help`
pub const objects_help =
    \\The `draw` command works with geometric objects and concepts.
    \\Use the commands below to explore each topic in detail.
    \\
    \\  zsat draw vec2d --help
    \\       2D vector data format, input shapes, coordinate systems
    \\  zsat draw vec2d style --help
    \\       Style attributes: coordinate system, orientation, steps, line properties
    \\  zsat draw vec2d output --help
    \\       Output transformations: anchor, rotate, scale, mirror
    \\  zsat draw point --help
    \\       How to define points: explicit coordinates or references
    \\  zsat draw line --help
    \\       How to define lines for the mirror transformation
    \\  zsat draw angle --help
    \\       How to represent angles: degrees, radians, and fractions of pi
    \\  zsat draw color --help
    \\       Available color names for line color
;

/// Print help text directly (used as execFn for doc-only subcommands).
pub fn printHelpExec(ctx: @import("zli").CommandContext) !void {
    if (ctx.command.cmd_options.help) |help| {
        try ctx.writer.print("{s}\n", .{help});
    }
    try ctx.writer.flush();
}
