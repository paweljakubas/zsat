# zsat

**Z**ig based **S**cience plot and **A**nimation command line **T*ool

[![Zig Version](https://img.shields.io/badge/Zig_Version-0.15.2-orange.svg?logo=zig)](README.md)
[![License: MIT](https://img.shields.io/badge/License-Apache 2.0-lightgrey.svg?logo=cachet)](LICENSE)
[![Built by paweljakubas](https://img.shields.io/badge/Built%20by-@paweljakubas-blue)](https://github.com/paweljakubas)

## Rationale to create **zsat**

As I have been hacking and performing numerical simulations I discovered a need for a tool using which I can quickly
visualize the result of the simulation, also with a capability to produce animation, without leaving a shell.
There are wonderful visualization tools used widely in scientific community, like **gnuplot**,
or libraries in Python/R/Julia ecosystems.

But they lack four features that are crucial for my workflow:
- they are not integrated with modern terminal emulators that have graphics support
- the paradigm of plot/animation construction in the current tools is not satisfactory for the person that have experienced [haskell diagrams](https://archives.haskell.org/projects.haskell.org/diagrams/)
- they are far away in terms of succinctness of data manipulation that one can realize in array languages like APL or J.
- it usually takes a long time to produce satisfactory animation

Hence, my attempt to address those pain pointsin this project.

I also treat it as an opportunity to learn and practice Zig, at this moment, my favorite system programming language.

## Backend
At this moment the only backend possible is based on haskell's diagrams library, meaning one needs
- ghc
- cabal
installed in the local system.

## Front end
If one wants PNG or GIF file as an output then no front end is required.

But if one want to have full experience I advocated for in the Rationale section then one needs
terminal emulator that implements [kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/),
like Kitty, WezTerm and Ghostty to name a few.
Alternatively one can use it with tools supporting the protocol, like [blackcat](https://github.com/j-c-m/blackcat).
