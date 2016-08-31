using Media, Lazy, Hiccup

import Media: render
import Hiccup: div

import Juno: Inline, Clipboard, Editor, Console

Media.@defpool Editor
Media.@defpool Console

setdisplay(Editor(), Any, Console())
setdisplay(Console(), Any, Console())

include("plots.jl")
include("view.jl")
include("objects.jl")
include("errors.jl")
