using Media, Lazy

import Media: render

type Inline end

for D in :[Editor, Workspace, Console].args
  @eval type $D end
  @eval let pool = @d()
    Media.pool(::$D) = merge(Media.pool(), pool)
    Media.setdisplay(::$D, T, input) = pool[T] = input
  end
  @eval setdisplay($D(), Any, $D())
end

# Console

render(::Console, x; options = @d()) =
  println(stringmime(MIME"text/plain"(), x))

render(::Console, ::Nothing; options = @d()) = nothing

# Editor

function splitresult(r)
  ls = split(r, "\n")
  @d(:header=>ls[1]*(length(ls)>1?" ...":""),
     :body=>join(ls[2:end], "\n"))
end

render(::Editor, x::Text; options = @d()) =
  splitresult(string(x))

render(e::Editor, x; options = @d()) =
  render(e, Text(stringmime(MIME"text/plain"(), x)), options = options)

render(e::Editor, ::Nothing; options = @d()) =
  render(e, Text("✓"), options = options)
