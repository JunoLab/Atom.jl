using Media, Lazy, Hiccup

import Media: render
import Hiccup: div

type Inline end

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

type Tree
  head
  children::Vector{Any}
end

tojson(x) = stringmime(MIME"text/html"(), x)
tojson(t::Tree) = Any[tojson(t.head), map(tojson, t.children)]

render(i::Inline, t::Tree; options = @d()) = t

render(::Inline, x::HTML; options = @d()) = x

render(::Inline, x::Node; options = @d()) = x

# Console

render(::Console, x; options = @d()) =
  msg("result", @d(:result=>tojson(render(Inline(), x, options = options)),
                   :error=>isa(x, EvalError)))

render(::Console, ::Nothing; options = @d()) = nothing

# Editor

render(e::Editor, ::Nothing; options = @d()) =
  render(e, Text("✓"), options = options)

render(::Editor, x; options = @d()) =
  render(Inline(), x, options = options)

include("objects.jl")
include("errors.jl")
include("methods.jl")
