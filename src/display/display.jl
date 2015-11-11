using Media, Lazy, Hiccup

import Media: render
import Hiccup: div

type Inline end
type Plain end

for D in :[Editor, Console].args
  @eval type $D end
  @eval let pool = @d()
    Media.pool(::$D) = merge(Media.pool(), pool)
    Media.setdisplay(::$D, T, input) = pool[T] = input
  end
end

setdisplay(Editor(), Any, Console())
setdisplay(Console(), Any, Console())

# Inline display

link(x, file) = a(@d("data-file"=>file), x == nothing ? basename(file) : x)

link(x, file, line::Integer) = link(x, "$file:$line")

link(file, line::Integer...) = link(nothing, file, line...)

render(::Inline, x::HTML; options = @d()) = stringmime(MIME"text/html"(), x)

render(::Inline, x::Node; options = @d()) = stringmime(MIME"text/html"(), x)

type Tree
  head
  children::Vector{Any}
end

function render(i::Inline, t::Tree; options = @d())
  r(x) = render(i, x, options = options)
  c(r(t.head), map(r, t.children))
end

istree(t) = isa(t, Vector) && length(t) == 2

type SubTree
  head
  child
end

function render(i::Inline, t::SubTree; options = @d())
  r(x) = render(i, x, options = options)
  sub = r(t.child)
  istree(sub) ? c(r(t.head)*sub[1], sub[2]) : r(span(".gutted", HTML(r(t.head)*sub)))
end

# Console

render(::Console, x; options = @d()) =
  msg("result", @d(:result=>render(Inline(), x, options = options)))

render(::Console, ::Void; options = @d()) = nothing

# Editor

render(e::Editor, ::Void; options = @d()) =
  render(e, Text("✓"), options = options)

render(::Editor, x; options = @d()) =
  render(Inline(), x, options = options)

render(::Plain, x) = stringmime(MIME"text/plain"(), x)

include("objects.jl")
include("errors.jl")
include("methods.jl")
