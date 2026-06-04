## First try and how to explore the tool

Let's say we have a vector in `xy` coordinate system `[1,1]` and want to plot it.
We can do it immediately by pasting the following:

```bash
λ echo '[[1,1]]' | zsat draw
```

![](fig1.png)

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

![](fig1.png)

There are many dimensions to master the tool and it is good to cover each aspect one by one.

## Data shape to be plotted

We piped `[1,1]` to the input. But, why we used double bracket in the end? Because `zsat` handles two types of vector structures that
need to be interpreted separately. And they are worth to be supported and treated differently.
In general, `zsat` differentiates three cases for further processing and presentation:

(a) multi-segment vector is treated as one structure
We already saw what `[[1,1]]` means - vector from (0,0) to (1,1).
`[[1,1], [-1,0]]` represents two-segment vector where `[-1,0]` starts where `[1,1]` ends.
Hence, enclosing the vectors between `[`and `]` means composing the two vectors in such a way
that 2-segment from (0,0) through (1,1) to (0,1) is formed.
Let's see it:

```bash
λ echo '[[1,1],[-1,0]]' | zsat draw
```

![](fig2.png)

(b) vectors that are gathered together 
If we write on the other hand `[[1,1]], [[-1,0]]` we have two vectors starting from (0,0). The frst one ending at (1,1), the second at (-1,0).
Gathering means all components will share the same style and, if processed, undergo the same transformation.

```bash
λ echo '[[1,1]],[[-1,0]]' | zsat draw
```

![](fig3.png)

(c) vectors are independent from each other

Each vector structure is interleaved by '\n' character which means each one constitute separate entity, with potentially different style and processing transformation.

```bash
λ echo '[[1,1]]\n[[-1,0]]' | zsat draw
```



