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

# Editor

render(e::Editor, ::Void) =
  render(e, Text("✓"))

render(::Editor, x) =
  render(Inline(), Copyable(x))

# Console

render(::Console, x) =
  @msg result(render(Inline(), Copyable(x)))

render(::Console, ::Void) = nothing

render(::Clipboard, x) = stringmime(MIME"text/plain"(), x)

include("plots.jl")
include("view.jl")
include("objects.jl")
include("methods.jl")
include("errors.jl")
