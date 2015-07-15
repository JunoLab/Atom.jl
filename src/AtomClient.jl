module AtomClient

using Lazy, JSON

global sock = nothing

isactive(sock::Nothing) = false
isactive(sock) = isopen(sock)

const handlers = Dict{UTF8String, Function}()

handle(f, t) = handlers[t] = f

function connect(port)
  global sock = Base.connect(port)
  @async while isopen(sock)
    result, id = nothing, nothing
    (t, data) = JSON.parse(sock)
    haskey(data, "callback") && (id = data["callback"])
    haskey(handlers, t) && (@errs result = handlers[t](data))
    isa(id, Integer) && msg(id, result)
  end
end

function msg(t, data)
  isactive(sock) || return
  println(sock, json(c(t, data)))
end

include("eval.jl")

end # module
