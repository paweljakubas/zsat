# zsat

**Z**ig based **S**cience plot and **A**nimation command line **T**ool

[![Zig Version](https://img.shields.io/badge/Zig_Version-0.15.2-orange.svg?logo=zig)](README.md)
[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%20License%202.0-blue)](LICENSE)
[![Built by paweljakubas](https://img.shields.io/badge/Built%20by-@paweljakubas-blue)](https://github.com/paweljakubas)

## Rationale to create **zsat**

As I have been hacking and performing numerical simulations I discovered a need for a tool using which I can quickly
visualize the result of the simulation, also with a capability to produce animation, without leaving a shell.
There are wonderful visualization tools used widely in scientific community, like **gnuplot**,
or countless libraries in Python/R/Julia ecosystems.

But they lack four features that are crucial for my workflow:
- they are not integrated with modern terminal emulators that have graphics support
- the paradigm of plot/animation construction in the current tools is not satisfactory for the person that has experienced workflow of a great [haskell diagrams](https://archives.haskell.org/projects.haskell.org/diagrams/) library
- they are far away in terms of succinctness of data manipulation that one can realize in array languages like APL or J (which I am huge fan)
- it usually takes a long time to produce satisfactory animation and feedback loop is too slow for me

Hence, my humble attempt to address those pain points as the goals of this project.

I also treat this as an opportunity to learn and practice Zig, a truely wonderful general programming language with a angle to be performant and low-level.

## Backend
At this moment the only backend possible is based on haskell's diagrams library, meaning one needs

```
- ghc
- cabal
```

installed in the local system. Please run `zsat setup show` to inspect if you are ready in backend sense.

## Front end
If one wants PNG or GIF file as an output then no front end is required.
You are good, but you will need to open the plot/run animation separately.
In order to have it add always `--output/-o FILE` to the `zsat` command.

But if one want to have full experience I advocated for, and enlisted as one of the four crucial features I am into in the Rationale section,
then one needs terminal emulator that implements [kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/),
like Kitty, WezTerm and Ghostty to name a few.
Alternatively one can use it with a tool supporting the protocol, like [blackcat](https://github.com/j-c-m/blackcat).

## Current state of the tool

```bash
./zig-out/bin/zsat --help
Zig-powered science animation and plot toolkit
v0.0.1

Usage: zsat [options]

Available commands:
   draw (d)        Construct figure from bits
   version (v)     Show zsat version

Flags:
   -h, --help      Shows the help for a command [Bool] (default: false)

Use "zsat [command] --help" for more information.



  (main) zsat λ ./zig-out/bin/zsat draw --help
Construct figure from bits

Usage: zsat draw [options]

Flags:
   -e0, --element0     Visual element that wil be contained in the figure. Visualization aspects are defined here. [String] (default: "cos tam")
   -h, --help          Shows the help for a command [Bool] (default: false)

Use "zsat draw --help" for more information.
```

## Zig packages (outside std) proudly used in the project:

- [**zli**](https://github.com/xcaeser/zli) for CLI development support
- [**macha**])(https://github.com/Hejsil/mecha) parser combinator library
- [**cmdtest**](https://github.com/pyk/cmdtest) for testing CLI app