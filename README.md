**Z**ig-based **S**cience plotting and **A**nimation command line **T**ool

[![Zig Version](https://img.shields.io/badge/Zig_Version-0.15.2-orange.svg?logo=zig)](README.md)
[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%20License%202.0-blue)](LICENSE)
[![Built by paweljakubas](https://img.shields.io/badge/Built%20by-@paweljakubas-blue)](https://github.com/paweljakubas)

## Rationale to create **zsat**

As I have been hacking and performing numerical simulations I discovered a need for a tool with which I can quickly
visualize the result of the simulation, also with a capability to rapidly produce the animation, without leaving a shell.
There are wonderful visualization tools, used widely in scientific community, like **gnuplot**,
or countless libraries in Python/R/Julia ecosystems.

But they lack five features that are crucial for my workflow:
- they are not integrated with modern terminal emulators that have graphics support
- the paradigm of plot/animation construction in the current tools is not satisfactory for the person that has worked with a great [haskell diagrams](https://archives.haskell.org/projects.haskell.org/diagrams/) library, is in pursuit of total control and expliciteness and fond of math
- they are far away in terms of succinctness of data manipulation that one can realize in array languages like APL or J (of which I am a huge fan), and the elegance of Haskell
- it usually takes a long time to produce a satisfactory animation using existent tools and the intermediate feedback loop is too slow for me
- it is not so staightforward to save customized templates that could be reused later and thanks to that accelerate the workflow

Hence, my humble attempt to address those pain points as the goals of this project.

I also treat this as an opportunity to learn and practice Zig, a truely wonderful general programming language with an angle to be performant, explicit and low-level.
As AI agentic era has started it is going to be probably more recreational programming project, but still, I do have a lot of fun developing it and do not intend to stop:-)

**zsat** must have had picked maximum two out of three choices from _flexibility_, _power_ and _simplicity_.
And, by a design, both __flexibility__ and __power__ were chosen over _simplicity_.
Meaning, if you are in pursuit of the simplicity **zsat** might not be the best choice.

## Terminal

If one wants to have a full experience I advocated for, and enlisted as one of the five crucial features in the Rationale section above,
then terminal emulator that implements [kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/) is required.
The terminals supporting **kitty graphics protocol** includes Kitty, WezTerm and Ghostty, to name a few.
`zsat` supports the protocol natively using [zigimg](https://github.com/zigimg/zigimg).

**Terminal detection**: `zsat` checks the `TERM` environment variable for kitty graphics protocol support (xterm, kitty, ghostty).
If not supported it is outputing to file automatically.

When `--out` is specified, irrespective of the terminal, output goes to file.

## Current state of the tool

```bash
$ zsat --help
Zig-powered science animation and plot command line tool
v0.0.1
<commit>

Usage: zsat [options]

Available commands:
   draw (d)        Construct figure from elements, sources, outputs, panes and frames
   version (v)     Show zsat version

Flags:
   -h, --help      Shows the help for a command [Bool] (default: false)

Use "zsat [command] --help" for more information.
```

### draw command

```bash
$ zsat draw --help
Construct figure for stdin data using styles, datum, outputs, panes and frames

Usage: zsat draw [options]

Flags:
   -d, --datum      Mapping data streams to the defined styles. [String] (default: "(vec) -> (vec -> e0)")
   -s, --styles     Style(s) definition to be used in further steps when constructing the figure. [String] (default: "e0:{vec2d xy fixed [lw:20, lc: black, lo: 100, le:none, lj: none, ld: none]}")
   --debug          Dump the drawing representation for a command invoked. [Bool] (default: false)
   -f, --frames     Frame(s) definition of the figure. [String] (default: "(out) -> out -> p0")
   -p, --panes      Pane(s) definition to be used in frame construction of the figure. [String] (default: "p0:{size: 600x600}")
   --out            Output filename for the PNG image. When specified, always writes to file instead of displaying in terminal. [String]
   -h, --help       Shows the help for a command [Bool] (default: false)
```

### Examples

Basic usage (single input stream - vectors connected from origin):
```bash
echo '[[1,1], [2,2]]' | zsat draw
```

Specify output file:
```bash
echo '[[1,1], [2,2]]' | zsat draw --out myplot.png
```

With custom size:
```bash
echo '[[1,1], [2,2]]' | zsat draw -p 'p0:{size: 1200x800}'
```

Multiple input streams - each line is a separate series starting from origin:
```bash
printf '[[1,0]]\n[[0,1]]' | zsat draw -d "(vec, vec) -> (vec -> e0)" -f "(out, out) -> out -> p0" -p 'p0:{size: 100x100}'
```

Multiple styles with different colors, line widths, and opacities:
```bash
echo -e '[[0,1]]\n[[1,1], [2,2]]\n[[-1,0], [-2,0]]' | zsat draw \
  -s 'e0:{vec2d xy fixed [lw:5, lc: red, lo: 100]}, e1:{vec2d xy fixed [lw:20, lc: green, lo: 50]}, e2:{vec2d xy fixed [lw:30, lc: blue, lo: 75]}' \
  -d '(vec1, vec2, vec3) -> (vec1 -> e0, vec2 -> e1, vec3 -> e2)' \
  -f '(out1, out2, out3) -> (out1 -> p0, out2 -> p0, out3 -> p0)'
```

Display in terminal (requires kitty graphics protocol support - Kitty, WezTerm, Ghostty):
```bash
printf '[[3,1], [-3,1]]\n[[2,-1]]' | zsat draw --datum "(vec, vec) -> (vec -> e0)" --frames "(out, out) -> out -> p0"
```

Note: When using multiple input streams, you must update `--datum` to match the number of inputs:
- `--datum "(vec, vec) -> (vec -> e0)"` for 2 inputs using the same style
- `--datum "(vec0, vec1) -> (vec0 -> e0, vec1 -> e1)"` for 2 inputs using different styles

Using anchor points to set explicit start positions for vector segments:
```bash
# out1 starts at (1,2), out2 starts at (0,0) - both must have explicit transformation
echo -e '[[0,1]]\n[[1,1], [2,2]]' | zsat draw \
  -s 'e0:{vec2d xy fixed [lw:5, lc: red, lo: 100]}, e1:{vec2d xy fixed [lw:20, lc: green, lo: 50]}' \
  -d '(vec1, vec2) -> (vec1 -> e0, vec2 -> e1)' \
  -o '(out1, out2) -> ((a {(1,2)}) out1, (a {(0,0)}) out2)'
```

Tip: Use `echo -e` instead of `echo` to ensure newlines are properly interpreted in the input data.

## Development

```
zig build
zig build test --summary all
```

## In-depth tutorial

[Go here](./Tutorials/Tutorial.md)

## Zig packages (outside std) proudly used in the project:

- [**zli**](https://github.com/xcaeser/zli) CLI development support (0.16.0 ready)
- [**mecha**](https://github.com/Hejsil/mecha) Parser combinator library (NOT 0.16.0 ready)
- [**cmdtest**](https://github.com/pyk/cmdtest) Testing of CLI app (NOT 0.16.0 ready)
- [**zigimg**](https://github.com/zigimg/zigimg) Image processing for **kitty graphics protocol** support (0.16.0 ready)
- [**z2d**](https://github.com/vancluever/z2d) 2d graphics backend (0.16.0 ready)