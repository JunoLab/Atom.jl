using Media, Lazy

import Media: render

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

type Tree
  head
  children::Vector{Any}
end

tojson(t::Tree) = Any[t.head, map(tojson, t.children)]

function splitstring(r)
  ls = split(r, "\n")
  @d(:header=>ls[1]*(length(ls)>1?" ...":""),
     :body=>join(ls[2:end], "\n"))
end

render(::Inline, x::Text; options = @d()) =
  splitstring(string(x))

render(d::Inline, x; options = @d()) =
  render(d, Text(stringmime(MIME"text/plain"(), x)), options = options)

# Console

render(::Console, x; options = @d()) =
  println(stringmime(MIME"text/plain"(), x))

render(::Console, ::Nothing; options = @d()) = nothing

# Editor

render(e::Editor, ::Nothing; options = @d()) =
  render(e, Text("✓"), options = options)

render(::Editor, x; options = @d()) =
  render(Inline(), x, options = options)
