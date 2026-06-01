### First try and how to explore the tool

Let's say we have a vector in `xy` coordinate system `[1,1]` and want to plot it.
We can do it immediately by pasting the following:

```bash
λ echo '[[1,1]]' | zsat draw
```

What you should see is a diagonal black line segment spanning whole figure having white-background.
`zsat` interpreted the input as vector, anchored it at (0,0), chose the line color and how it fits the figure, ie. that it fills
almost completely the available space.
As `zsat` aims to be powerful and expressive the aspiring user might request the way to look at those default settings, as well as altering it.
And this is exactly what `--debug` optional argument offers - a peek of what the tool sets exactly during the call.

```bash
λ echo '[[1,1]]' | zsat draw --debug
stdin:
[[1,1]]

--styles e0:{vec2d xy fixed last [lw:10, lc: black, lo: 100, le:none, lj: none, ld: none]}
--datum (vec) -> (vec -> e0)
--outputs (out) -> (anchor {(0,0)}) out
--panes p0:{size: 600x600}
--frames (out) -> out -> p0
```

There are many dimensions and it is good to cover each aspect one by one.


