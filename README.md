**Z**ig-based **S**cience plotting and **A**nimation command line **T**ool

[![Zig Version](https://img.shields.io/badge/Zig_Version-0.16.0-orange.svg?logo=zig)](README.md)
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

Available commands:
   color           Available color names for line color
   line            How to define lines for the mirror transformation
   objects         Overview of objects and concepts you can explore
   point           How to define points: explicit coordinates or references
   vec2d           2D vector data format and concepts

Flags:
   --out            Output filename for the PNG image. When specified, always writes to file instead of displaying in terminal.
   -d, --datum      Mapping data streams to the defined styles.
                    Default: "(vec) -> (vec -> e0)"
   -s, --styles     Style(s) definition to be used in further steps when constructing the figure.
                    Default: "e0:{vec2d xy fixed last [lw:10, lc: black, lo: 100, le:none, lj: none, ld: none]}"
   --debug          Dump the drawing representation for a command invoked.
   -o, --outputs    Input(s) transformation definition of the outputs.
                    Default: "(out) -> (anchor {(0,0)}) out"
   -f, --frames     Frame(s) definition of the figure.
                    Default: "(out) -> out -> p0"
   -p, --panes      Pane(s) definition to be used in frame construction of the figure.
                    Default: "p0:{size: 600x600}"
   -h, --help       Shows the help for a command
```

To explore available concepts and objects, run:

```bash
zsat draw objects --help
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

Tip: Use `echo -e` instead of `echo` to ensure newlines are properly interpreted in the input data.

## In-depth tutorial

[New to zsat -> go here](./Tutorials/FirstTutorial.md)

## Development

```
zig build
zig build test --summary all
```

## Zig packages (outside std) proudly used in the project:

- [**zli**](https://github.com/xcaeser/zli) CLI development support 
- [**mecha**](https://github.com/Hejsil/mecha) Parser combinator library 
- [**cmdtest**](https://github.com/pyk/cmdtest) Testing of CLI app 
- [**zigimg**](https://github.com/zigimg/zigimg) Image processing for **kitty graphics protocol** support 
- [**z2d**](https://github.com/vancluever/z2d) 2d graphics backend 