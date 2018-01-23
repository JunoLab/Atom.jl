using Media, Lazy, Hiccup

import Media: render
import Hiccup: div

import Juno: Inline, Clipboard, Editor, Console, undefs, fade, icon

Media.@defpool Editor
Media.@defpool Console

setdisplay(Editor(), Any, Console())
setdisplay(Console(), Any, Console())

include("base.jl")
include("plots.jl")
include("view.jl")
include("lazy.jl")
include("errors.jl")
