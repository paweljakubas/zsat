## First try and how to explore the tool

Let's say we have a vector in `xy` coordinate system `[1,1]` and want to plot it.
We can do it immediately by pasting the following:

<div style="background-color: #f6f8fa; padding: 16px; border-radius: 6px; margin-bottom: 16px;">

```bash
λ echo '[[1,1]]' | zsat draw
```

<img src="fig1.png" width="300">

</div>

What you should see is a diagonal black line segment spanning whole figure having white-background.
`zsat` interpreted the input as vector, anchored it at (0,0), chose the line color and how it fits the figure, ie. that it fills
almost completely the available space.
As `zsat` aims to be powerful and expressive the aspiring user might request the way to look at those default settings, as well as altering it.
And this is exactly what `--debug` optional argument offers - a peek of what the tool sets exactly during the call.

<div style="background-color: #f6f8fa; padding: 16px; border-radius: 6px; margin-bottom: 16px;">

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

<img src="fig1.png" width="300">

</div>

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

<div style="background-color: #f6f8fa; padding: 16px; border-radius: 6px; margin-bottom: 16px;">

```bash
λ echo '[[1,1],[-1,0]]' | zsat draw
```

<img src="fig2.png" width="300">

</div>

(b) vectors that are gathered together 
If we write on the other hand `[[1,1]], [[-1,0]]` we have two vectors starting from (0,0). The frst one ending at (1,1), the second at (-1,0).
Gathering means all components will share the same style and, if processed, undergo the same transformation.

<div style="background-color: #f6f8fa; padding: 16px; border-radius: 6px; margin-bottom: 16px;">

```bash
λ echo '[[1,1]],[[-1,0]]' | zsat draw
```

<img src="fig3.png" width="300">

</div>

(c) vectors are independent from each other

Each vector structure is interleaved by '\n' character which means each one constitute separate entity, with potentially different style and processing transformation.

```bash
λ echo '[[1,1]]\n[[-1,0]]' | zsat draw
Error: failed to parse input data. Please check your input format.
```

The error stems from the fact that we have two outputs, as each row constitute one output, and we have `--outputs (out) -> (anchor {(0,0)}) out` in the default setting.
In order to handle that correctly we need to specify two outputs, for example, `--outputs (out1, out2) -> ((anchor {(0,0)}) out1, (anchor {(1,1)}) out2)`.
More on this later. Here, we are into understanding how input looks like, and what kind of shapes are supported. 


