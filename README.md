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
- They are not integrated with modern terminal emulators that support graphics.
- The paradigm for constructing plots and animations in existing tools is not satisfactory for someone who has worked with the excellent [Haskell Diagrams](https://archives.haskell.org/projects.haskell.org/diagrams/) library, values total control and explicitness, and has a strong mathematical inclination.
- They fall short in terms of the succinctness of data manipulation achievable in array languages like APL or J (of which I am a huge fan), as well as the elegance of Haskell.
- Producing a satisfactory animation usually takes too long with existing tools, and the intermediate feedback loop is too slow for me.
- It is not straightforward to save customized templates for reuse to accelerate the workflow.

Hence, my humble attempt to address those pain points as the goals of this project.

I also treat this as an opportunity to learn and practice Zig, a truly wonderful general-purpose programming language that is performant, explicit, and low-level.
With the rise of AI agents, this is likely to remain more of a recreational programming project, but I still have a lot of fun developing it and do not intend to stop!
**zsat** must have had picked maximum two out of three choices from _flexibility_, _power_ and _simplicity_.
And, by a design, both __flexibility__ and __power__ have been chosen over _simplicity_.
This means that if simplicity is your top priority, **zsat** may not be the best choice for you.

## Terminal

If one wants to have a full experience I advocated for, and enlisted as one of the five crucial features in the Rationale section above,
then terminal emulator that implements [kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/) is required.
Terminals that support the Kitty graphics protocol include Kitty, WezTerm, and Ghostty, to name a few.
`zsat` supports this protocol natively using [zigimg](https://github.com/zigimg/zigimg).

**Terminal detection**: `zsat` checks the `TERM` environment variable to detect Kitty graphics protocol support (e.g., xterm, kitty, ghostty).
If not supported, output is automatically written to a file.

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
Construct a figure from stdin data using styles, datum mappings, outputs, panes, and frames.

Usage: zsat draw [options]

To explore help more try: zsat draw objects --help

Flags:
   --out             Output filename for the PNG image. When specified, always writes to file instead of displaying in terminal.
   --overwrite       Let --save replace a key that is already defined in the target namespace instead of failing.
   --save            Persist a style defined in --styles into ~/.config/zsat/zsat.conf as NS::KEY, e.g. --save mynamespace::e1. The namespace is created when it does not exist yet.
   -d, --datum       Mapping data streams to the defined styles. Omitted, the first data input is associated with the firstly defined style, the second one with the secondly defined style, and so on, wrapping around when there are more inputs than styles.
   -s, --styles      Style(s) definition to be used in further steps when constructing the figure.
                     Default: "e0:{vec2d xy fixed last [l:10, c: black, o: 100, e:none, j: none, d: none]}"
   --debug           Dump the drawing representation for a command invoked.
   -o, --outputs     Input(s) transformation definition of the outputs.
                     Default: "(out) -> (anchor {(0,0)}) out"
   -f, --frames      Frame(s) definition of the figure.
                     Default: "(out) -> out -> p0"
   -p, --panes       Pane(s) definition to be used in frame construction of the figure.
                     Default: "p0:{size: 600x600}"
   -h, --help        Shows the help for a command
```

To explore the available concepts and objects, run:

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

With a pane border:
```bash
echo '[[1,1], [2,2]]' | zsat draw -p 'p0:{size: 600x600, border: [w:30, c:red]}'
```

Tip: Use `echo -e` instead of `echo` to ensure newlines are properly interpreted in the input data.

## In-depth tutorial

[New to zsat ? -> go here](./Tutorials/FirstTutorial.md)

## Roadmap

| Version | Planned Features |
| --- | --- |
| 0.2.0 | ✅ Done vector, line, persistance, text, axis, border, background, one-arg parameter combinators (hook, train), compose, power |
| 0.3.0 | polygons |
| 0.4.0 | curves |
| 0.5.0 | multi-styles for `all` |
| 0.6.0 | animations |
| 0.7.0 | view functionality |
| 0.8.0 | matrix2d grid |
| 0.9.0 | multipane functionality |
| 0.10.0 | matrix2d contour |
| next | dyadic ops, recall functionality, encapsulations, legends, arrows, J+zsat video demos |

## Contributions

Contributions are welcome! However, all contributions must be submitted through a separate branch and must fall into one of the following categories:

- Documentation enhancements
- Features that comply with the roadmap
- Bug fixes

## Development

```
zig build
zig build test --summary all
```

## Triggering a release

To create a new release:

1. **Tag the commit** on `main` (or the target commit) with a version matching `v*`:
   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```

2. **Wait for the workflow**. Pushing the tag triggers the Release GitHub Actions workflow, which builds binaries for `linux-x86_64`, `macos-aarch64`, and `macos-x86_64`, packages them as `.tar.gz`, generates a `sha256sums.txt` file, and creates a **draft release** with auto-generated release notes.

3. **Publish the draft**. Open the draft release on the GitHub Releases page, review the notes and attached files, and click "Publish release" to make it public.

## Zig packages (outside std) proudly used in the project:

- [**zli**](https://github.com/xcaeser/zli) CLI development support
- [**mecha**](https://github.com/Hejsil/mecha) Parser combinator library
- [**cmdtest**](https://github.com/pyk/cmdtest) Testing of CLI app
- [**zigimg**](https://github.com/zigimg/zigimg) Image processing for **kitty graphics protocol** support
- [**z2d**](https://github.com/vancluever/z2d) 2d graphics backend

---

## License

Apache-2.0
