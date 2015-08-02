module Atom

using Lazy, JSON

include("comm.jl")
include("eval.jl")
include("completions.jl")
include("misc.jl")
include("frontend.jl")
include("utils.jl")

function __init__()
  include("patch.jl")
end

end # module
