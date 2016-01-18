using Media, Lazy, Hiccup

import Media: render
import Hiccup: div

type Inline end
type Plain end

type Editor end
type Console end

Media.@defpool Editor
Media.@defpool Console

setdisplay(Editor(), Any, Console())
setdisplay(Console(), Any, Console())

# Console

render(::Console, x; options = d()) =
  msg("result", d(:result=>render(Inline(), x, options = options)))

render(::Console, ::Void; options = d()) = nothing

# Editor

render(e::Editor, ::Void; options = d()) =
  render(e, Text("✓"), options = options)

render(::Editor, x; options = d()) =
  render(Inline(), x, options = options)

render(::Plain, x; options = d()) = stringmime(MIME"text/plain"(), x)

render(::Inline, x; options = d()) = render(Plain(), x, options = options)

include("view.jl")
include("objects.jl")
include("methods.jl")
include("errors.jl")
