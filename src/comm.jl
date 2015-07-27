global sock = nothing

isactive(sock::Nothing) = false
isactive(sock) = isopen(sock)

const handlers = Dict{UTF8String, Function}()

handle(f, t) = handlers[t] = f

id = 0
const callbacks = Dict{Int,Condition}()

function connect(port)
  global sock = Base.connect(port)
  @async while isopen(sock)
    let # Don't let tasks close over the same t, data
      t, data = JSON.parse(sock)
      @schedule try
        result, id = nothing, nothing
        haskey(data, "callback") && (id = data["callback"])
        delete!(data, "callback")
        if haskey(handlers, t)
          result = handlers[t](data)
        elseif haskey(callbacks, t)
          notify(callbacks[t], data)
          delete!(callbacks, t)
        else
          warn("Atom.jl: unrecognised message $t.")
        end
        isa(id, Integer) && msg(id, result)
      catch e
        msg("error", @d(:msg=>"Julia Client – Internal Error",
                        :detail=>sprint(showerror, e, catch_backtrace())))
      end
    end
  end
end

function msg(t, data)
  isactive(sock) || return
  println(sock, json(c(t, data)))
end

function rpc(t, data)
  i, c = (global id += 1), Condition()
  callbacks[i] = c
  data["callback"] = i
  msg(t, data)
  return wait(c)
end
