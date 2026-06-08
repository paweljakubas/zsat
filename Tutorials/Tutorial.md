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
Error: failed to parse input data. Please check your input format.
```

The error stems from the fact that we have two outputs, as each row constitute one output, and we have `--outputs (out) -> (anchor {(0,0)}) out` in the default setting.
In order to handle that correctly we need to specify two outputs, for example, `--outputs (out1, out2) -> ((anchor {(0,0)}) out1, (anchor {(1,1)}) out2)`.
More on this later. Here, we are into understanding how input looks like, and what kind of shapes are supported. 

## Defining styles

The tool provides the default style for the user:

`e0:{vec2d xy fixed last [lw:10, lc: black, lo: 100, le:none, lj: none, ld: none]}`.

Let's decompose what every part means.

`e0` denotes that in other options this particular style is going to be defined by `e0` key.
Once defined in ``styles` option one can reuse the defined element by using `e0`.

What follows, i.e., `{...}`, is the definition body of `e0`, in another words the corresponding value of it.
Here, many things happen and could be influenced.

First of all, `vec2d` is telling how data should be treated - here, we want data in stdin to be treated as 2D vector.
It means we have at the input the data that complies with vector 2d shape, meaning is parsable as specified in the previous section.

`xy` denotes that data values, for example, `[1,2]` should be interpreted in XY coordinate system, and hence `x=1, y=2` there.
We have also polar coordinate system available, which is invoked by writing `polar` rather than `xy`. In that case `[1,30]` would be
interpreted as `r=1, phi=30 degrees`. More on that later.

`fixed` is the setting that is relevant only for n-segment vectors, and here it denotes that each consecutive segment does not depend on its predecessor location and orientation,
and its coordinate pair is expressed with regards to global x and y axis. This setting could be changed to either 'origin' or 'coord' which both redefine coordination system
in which values are defined based on the previous segment, if present. More on this later.

`last` means that we request only last image of the vector to be plotted, which will become relevant when we introduce operations which, if composed between each other, create many intermediary images that end with the final one. 'last' denotes that we want only the final image to be plotted, `all` means the user wants all, i.e.,  intermediary and final, images to be plotted. More on that later.

`[..]` is vector styling setting, `lw` meaning `line width` expressed in pixels, `lc` meaning `line color`, `lo` meaning `line opacity` where 0 is totally transparent, 100 is totally opaque,
`le` meaning `line ending` where besides default 'none' we can choose: `butt`, `round` or `square`. `lj` stands for `line join` and is relevant for n-segment vectors and describes how two segments are attached to each other. With default `none` user has also choices: `mitter`, `round` and `bevel`.
`ld` stands for `line dashing` that is switched off by default, meaning continuous line is to be used. In case one wants to use it several things needs to be explicitely provided: first when the first dash is to be started (by pixel number), succeded by providing pattern `[dash1, off1, dash2, off2,..]` which means the width of the first dash, `dash1`, then empty space, `off1`, and so on. Everything expressed in pixels. If the overall length of dashes and empty spaces between `[..]` is less than the vector to be covered, after covering the whole length of `[..]` the next dashing pattern is overlapped, and so on. We will see examples, soon.

Let's start with vector styles and jump immediately to the example.

```bash
λ echo '[[1,1]]' | zsat draw --styles 'e0{[lw:15, lc: aqua]}'
```
![](fig4.png)

We reused `e0` style definition from default and change line width to `15` and line color to `aqua`.
Another example below.

```bash
λ echo '[[1,1]]' | zsat draw --styles 'e0{[lw:15, lc: aqua, lo: 20]}'
```
![](fig5.png)
