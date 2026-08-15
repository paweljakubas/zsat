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
    \\  printf '[[1,1]]\n[[0,1]]' | zsat draw -s 'e0:{vec2d}, e1:{[c:red]}' \\
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
    \\  l:N  -- line width in pixels (default: 10)
    \\  c:NAME  -- line color, any CSS color name (default: black)
    \\  o:N  -- line opacity, 0..100 (default: 100)
    \\  e:MODE  -- line ending: none | butt | round | square (default: none)
    \\  j:MODE  -- line join: none | miter | round | bevel (default: none)
    \\  d:[D1,O1,D2,O2,...] OFFSET  -- dashing pattern and offset in pixels
    \\
    \\Style inheritance:
    \\  e1: e0{[c: red]}     -- e1 copies e0, then overrides c to red
    \\  e2: e1{[d: [10,5] 0]}  -- e2 copies e1, then adds dashing
    \\
    \\Examples:
    \\  e0:{vec2d xy fixed last [l:15, c: aqua]}
    \\  e0:{vec2d polar origin all [l:5, c: red, d: [40,10] 0]}
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
    \\  center            -- replace the vector chain with the point at its center:
    \\                       for a single vector this is the middle of the vector;
    \\                       for a chain of vectors it is the centroid of the
    \\                       segment midpoints weighted by segment length
    \\
    \\Shorthand forms:
    \\  a   -- anchor
    \\  r   -- rotate
    \\  s   -- scale
    \\  m   -- mirror
    \\  p   -- project
    \\  o   -- orthogonal
    \\  c   -- center
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
    \\  (out) -> (c) out                    -- collapse the chain to its center point
;

/// Help text for `zsat draw pt2d --help`
pub const pt2d_help =
    \\Points are an input format for `zsat draw`. Each point is drawn as a
    \\marker (circle or square) at its coordinates, using the point's style.
    \\
    \\Input shape:
    \\  stdin delivers one or more data rows, separated by newlines.
    \\  Each row is a comma-separated list of points enclosed in {...}.
    \\
    \\  {(x1,y1)}                  -- a single point
    \\  {(x1,y1), (x2,y2), ...}    -- multiple points (gathered, same style)
    \\  {(x1,y1)}\n{(x2,y2)}      -- two separate data rows (different styles possible)
    \\
    \\  {(1,1)}                    -- one point at (1,1)
    \\  {(0,0), (1,0), (0,1)}      -- three points in one row
    \\
    \\Coordinate systems:
    \\  xy     -- values are (x, y) in Cartesian space
    \\  polar  -- values are (r, phi) where phi is an angle
    \\
    \\Every point in a row shares the same style and is drawn as a marker.
    \\  See `zsat draw pt2d style --help` for the available attributes.
    \\
    \\Output:
    \\  Use the identity output `(pt) -> pt` to draw the raw input points.
    \\  Points can also be anchored, rotated, mirrored and projected before
    \\  drawing. See `zsat draw pt2d output --help` for the available operations.
    \\
    \\Examples:
    \\  printf '{(1,1)}' | zsat draw -s 'e0:{pt2d [sh:circle, s:10]}' -o '(pt) -> pt'
    \\  printf '{(0,0), (1,0), (0,1)}' | zsat draw \\
    \\    -s 'e0:{pt2d [sh:square, s:5, c: red]}' -o '(pt) -> pt'
;

/// Help text for `zsat draw pt2d style --help`
pub const pt2d_style_help =
    \\Style definition syntax:
    \\  eN:{pt2d COORDINATE-SYSTEM [ATTRIBUTES]}
    \\
    \\  eN     -- style key (e0, e1, ...) used for referencing in --datum
    \\  {...}  -- style body; all fields are optional and inherit from defaults
    \\
    \\TYPE:
    \\  pt2d  -- input is parsed as 2D points and drawn as markers
    \\
    \\COORDINATE SYSTEM (default: xy):
    \\  xy     -- values are (x, y) Cartesian coordinates
    \\  polar  -- values are (r, phi) where phi is an angle
    \\
    \\ATTRIBUTES inside [...]:
    \\  sh:MODE  -- marker shape: circle | square (default: circle)
    \\  s:N      -- marker size in pixels; diameter for circles,
    \\              side length for squares (default: 10)
    \\  c:NAME   -- marker color, any CSS color name (default: black)
    \\  o:N      -- marker opacity, 0..100 (default: 100)
    \\
    \\Examples:
    \\  e0:{pt2d [sh:square, s:5]}
    \\  e0:{pt2d [sh:circle, s:8, c: red, o: 50]}
    \\  e0:{pt2d polar [sh:circle, s:8]}
;

/// Help text for `zsat draw pt2d output --help`
pub const pt2d_output_help =
    \\The --outputs expression defines how each point row is transformed and anchored.
    \\
    \\Syntax:
    \\  (pt0, pt1, ...) -> (EXPR0, EXPR1, ...)
    \\
    \\Each EXPR is a composition of operations applied right-to-left:
    \\  (op3 & op2 & op1) pt   means   op3( op2( op1( pt ) ) )
    \\
    \\Available operations for points:
    \\
    \\  anchor POINT      -- move the point set so its centroid lands on POINT:
    \\                       a single point moves exactly onto POINT, multiple
    \\                       points all shift by the same (POINT - centroid) vector
    \\  rotate ANGLE around POINT  -- rotate counter-clockwise by ANGLE degrees
    \\  mirror (LINE)     -- reflect the point(s) across LINE
    \\  project TARGET    -- project the point(s) onto a line or direction
    \\  center            -- replace the point(s) with their centroid (average position)
    \\
    \\Operations that do NOT make sense for points and are rejected:
    \\  scale SX,SY       -- a point carries no magnitude to scale
    \\  orthogonal TARGET -- a point carries no direction for an orthogonal component
    \\
    \\Shorthand forms:
    \\  a   -- anchor
    \\  r   -- rotate
    \\  m   -- mirror
    \\  p   -- project
    \\  c   -- center
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
    \\TARGET for project:
    \\  (LINE)            -- a line, e.g. (y=0) or (y=2x+1)
    \\  outN              -- reference to another output's direction
    \\
    \\Examples:
    \\  (pt) -> pt                          -- draw raw input points
    \\  (pt) -> (a {(0,0)}) pt              -- shift points so centroid lands on (0,0)
    \\  (pt) -> (r [90 a (0% self)] & a {(0,0)}) pt  -- rotate 90 degrees
    \\  (pt) -> (m (y=x) & a {(0,0)}) pt    -- mirror across y=x
    \\  (pt) -> (p (y=0) & a {(0,0)}) pt    -- project onto the line y=0
    \\  (pt) -> (c) pt                      -- collapse all points to their centroid
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
    \\Colors are specified by name in the `c` (color) attribute.
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
    \\  c: black
    \\  c: aqua
    \\  c: lightcoral
    \\  c: rebeccapurple
;

/// Help text for `zsat draw border --help`
pub const border_help =
    \\Borders can be added to panes to frame the drawing area.
    \\
    \\Defining borders in --styles (reusable):
    \\  bN: {border [ATTR1, ATTR2, ...]}
    \\  bN: {border}               -- use all defaults
    \\
    \\Attributes (defaults: w=10, c=black, o=100):
    \\  width:N  or  w:N   -- border thickness in pixels
    \\  opacity:N  or  o:N -- opacity from 0 to 100
    \\  color:NAME  or  c:NAME -- any CSS color name
    \\
    \\Using borders in --panes:
    \\  border: bN               -- reference a named border defined in --styles
    \\  border: [ATTR1, ...]     -- inline border definition
    \\
    \\When a border is present, the plot elements are inset by the border
    \\width so they do not overlap the frame. For example, a 600-wide pane
    \\with a border width of 30 leaves 540 pixels for the plot content.
    \\
    \\Examples:
    \\  --styles 'b0: {border [w:30, c:red]}' --panes 'p0:{size: 600x600, border: b0}'
    \\  --panes 'p0:{size: 600x600, border: [w:20, c:blue]}'
    \\  --styles 'b1: {border}' --panes 'p1:{border: b1}'
;

/// Help text for `zsat draw axis --help`
pub const axis_help =
    \\Axes are reference lines that can carry ticks and value labels.
    \\They are defined in --styles and drawn in --outputs between two points.
    \\
    \\Defining axes in --styles (reusable):
    \\  aN: {axis line:[ATTR1, ...], ticks:[...], values:[...]}
    \\  aN: {axis line:[ATTR1, ...]}     -- only the line
    \\  aN: {axis}                       -- use all defaults
    \\
    \\LINE attributes (defaults: s=2, c=black, o=100):
    \\  size:N  or  s:N      -- line thickness in pixels
    \\  color:NAME  or  c:NAME -- any CSS color name
    \\  opacity:N  or  o:N   -- opacity from 0 to 100
    \\
    \\TICKS attributes:
    \\  pos:LIST  or  p:LIST -- positions along the axis where ticks are drawn
    \\  style:[ATTR1, ...]   -- tick styling (see below)
    \\
    \\VALUES attributes:
    \\  vals:LIST  or  v:LIST -- values labeled along the axis
    \\  style:[ATTR1, ...]    -- label styling (see below)
    \\
    \\LIST syntax (for pos and vals):
    \\  2, 4, 6, 8          -- explicit positions
    \\  2, 4, .., 10        -- range; step is the difference of the first two values
    \\  10, 8, .., 2        -- descending range
    \\
    \\TICK STYLE attributes (defaults: s=1, c=black, o=100, h=5, f=above):
    \\  size:N  or  s:N      -- tick line width in pixels
    \\  height:N  or  h:N    -- tick length in pixels
    \\  form:MODE  or  f:MODE -- above | middle | below | dot | square
    \\  color:NAME  or  c:NAME
    \\  opacity:N  or  o:N
    \\
    \\VALUE STYLE attributes (defaults: s=12, c=black, o=100, sp=2, f=above, a=0):
    \\  size:N  or  s:N      -- font size in pixels
    \\  font:PATH            -- font file; "default" uses the built-in font
    \\  spacing:N  or  sp:N  -- gap between the tick and its label in pixels
    \\  form:MODE  or  f:MODE -- above | middle | below | dot | square
    \\  angle:ANGLE  or  a:ANGLE -- rotation of the label counter-clockwise
    \\                         from the axis direction; 0 = the label reads
    \\                         along the axis (horizontal text on a horizontal
    \\                         axis). ANGLE uses the same syntax as rotate:
    \\                         90, -45, 1r4p (=pi/4), p (=pi), etc.
    \\  color:NAME  or  c:NAME
    \\  opacity:N  or  o:N
    \\
    \\Value labels are always placed beyond the tick tip, on the side the tick
    \\points to (form above/below), offset by the spacing -- regardless of
    \\whether the axis is horizontal, tilted, or vertical.
    \\
    \\The form direction is relative to the axis direction from the FROM point
    \\to the TO point: above lies to the left of the direction, below to the right.
    \\
    \\Axis inheritance (style update rules):
    \\  aN: aM {ATTRIBUTES}  -- axis aN copies axis aM, then overrides the given
    \\                         line/ticks/values attributes. Sections not
    \\                         mentioned (and fields not written) are inherited.
    \\  a0: a1 {values:[vals:1,2,3]}  -- reuse a1's line and ticks, relabel values
    \\  The base aM must be defined before aN in --styles; referencing an
    \\  undefined base is an error.
    \\
    \\Drawing axes in --outputs:
    \\  ft {FROM} {TO} aN      -- draw axis aN between the two points
    \\  fromTo {FROM} {TO} aN  -- long form
    \\  POINTS are given as {(X, Y)} pairs; see `zsat draw point --help`.
    \\  The referenced aN must be defined in --styles.
    \\
    \\Examples:
    \\  --styles 'a0: {axis line:[c:black, s:2], ticks:[pos:0,1,..,2], values:[vals:0,1,..,2]}'
    \\  --outputs '(out) -> ((a {(0,0)}) out, ft {(0,0)} {(2,0)} a0)'
    \\  --styles 'a1: {a line:[c:grey, o:50]}'
    \\  --styles 'a1: {a line:[c:grey, o:50]}, a0: a1 {values:[vals:1,2,3]}'
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
    \\       Output transformations: anchor, rotate, scale, mirror, center
    \\  zsat draw pt2d --help
    \\       Point input format, markers, and style attributes
    \\  zsat draw pt2d style --help
    \\       Point style attributes: shape, size, color, opacity
    \\  zsat draw point --help
    \\       How to define points: explicit coordinates or references
    \\  zsat draw line --help
    \\       How to define lines for the mirror transformation
    \\  zsat draw angle --help
    \\       How to represent angles: degrees, radians, and fractions of pi
    \\  zsat draw color --help
    \\       Available color names for line color
    \\  zsat draw border --help
    \\       How to define pane borders: width, opacity, and color
    \\  zsat draw axis --help
    \\       How to define axes: line, ticks, and value labels
;

/// Print help text directly (used as execFn for doc-only subcommands).
pub fn printHelpExec(ctx: @import("zli").CommandContext) !void {
    if (ctx.command.cmd_options.help) |help| {
        try ctx.writer.print("{s}\n", .{help});
    }
    try ctx.writer.flush();
}
