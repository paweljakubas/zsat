# zsat

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

**zsat** must have had picked maximum two out of three choices from _flexibility_, _power_ and _simplicity_.
And, by a design, both __flexibility__ and __power__ were chosen over _simplicity_.
Meaning, if you are in pursuit of the simplicity **zsat** might not be the best choice.

## Backend
The tool uses `z2d` under the hood to create 'png' panes which are later merged using `ffmpeg`.
Hence, **ffmpeg** is required.

## Front end
If one wants PNG or GIF file as an output then no front end is required.
You are good, but you will need to open the plot/run animation separately - for example, in separate window.

If one wants to have a full experience I advocated for, and enlisted as one of the five crucial features in the Rationale section above,
then terminal emulator that implements [kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/) is required.
The terminals supporting **kitty graphics protocol** includes Kitty, WezTerm and Ghostty, to name a few.
`zsat` enables using a tool supporting the protocol via [blackcat](https://github.com/j-c-m/blackcat) under the hood.
Meaning **blackcat** is also required to be installed.

## Current state of the tool

```bash
$ zsat --help
Zig-powered science animation and plot toolkit
v0.0.1

Usage: zsat [options]

Available commands:
   draw (d)        Construct figure from bits
   version (v)     Show zsat version

Flags:
   -h, --help      Shows the help for a command [Bool] (default: false)

Use "zsat [command] --help" for more information.
```

## Development

```
zig build
zig build test --summary all
```

## Tutorials

Vector plots - coming soon!

## Zig packages (outside std) proudly used in the project:

- [**zli**](https://github.com/xcaeser/zli) for CLI development support
- [**macha**](https://github.com/Hejsil/mecha) parser combinator library
- [**cmdtest**](https://github.com/pyk/cmdtest) for testing CLI app
- [**blackcat**](https://github.com/j-c-m/blackcat) cat enabling png/gif opening valid in **kitty graphics protocol** supported terminals