module Atom

using Lazy, JSON

include("utils.jl")

global sock = nothing

isactive(sock::Nothing) = false
isactive(sock) = isopen(sock)

const handlers = Dict{UTF8String, Function}()

handle(f, t) = handlers[t] = f

function connect(port)
  global sock = Base.connect(port)
  @async while isopen(sock)
    try
      result, id = nothing, nothing
      (t, data) = JSON.parse(sock)
      haskey(data, "callback") && (id = data["callback"])
      delete!(data, "callback")
      if haskey(handlers, t)
        result = handlers[t](data)
      end
      isa(id, Integer) && msg(id, result)
    catch e
      msg("error", @d(:msg=>"Julia Client – Internal Error",
                      :detail=>sprint(showerror, e, catch_backtrace())))
    end
  end
end

function msg(t, data)
  isactive(sock) || return
  println(sock, json(c(t, data)))
end

include("eval.jl")
include("completions.jl")
include("misc.jl")

end # module
