using Media, Lazy, Hiccup

import Media: render
import Hiccup: div

type Inline end
type Clipboard end

type Editor end
type Console end

Media.@defpool Editor
Media.@defpool Console

setdisplay(Editor(), Any, Console())
setdisplay(Console(), Any, Console())

# Console

render(::Console, x; options = d()) =
  @msg result(render(Inline(), x, options = options))

render(::Console, ::Void; options = d()) = nothing

# Editor

render(e::Editor, ::Void; options = d()) =
  render(e, Text("✓"), options = options)

render(::Editor, x; options = d()) =
  render(Inline(), x, options = options)

render(::Clipboard, x; options = d()) = stringmime(MIME"text/plain"(), x)

include("view.jl")
include("objects.jl")
include("methods.jl")
include("errors.jl")
