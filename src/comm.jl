global sock = nothing

macro mutex(ex)
  @gensym lock
  eval(current_module(), :(const $lock = Base.ReentrantLock()))
  quote
    lock($(esc(lock)))
    $(esc(ex))
    unlock($(esc(lock)))
  end
end

isactive(sock::Void) = false
isactive(sock) = isopen(sock)

macro ierrs(ex)
  :(try
      $(ex)
    catch e
      msg("error", @d(:msg=>"Julia Client – Internal Error",
                      :detail=>sprint(showerror, e, catch_backtrace()),
                      :dismissable=>true))
    end)
end

function connect(port)
  exit_on_sigint(false)
  global sock = Base.connect(port)
  @async while isopen(sock)
    @ierrs let # Don't let tasks close over the same t, data
      t, data = JSON.parse(sock)
      @schedule @ierrs handlemsg(t, data)
    end
  end
end

function msg(t, data)
  isactive(sock) || return
  # this println is supposed to be atomic, but it doesn't seem to be.
  @mutex res = println(sock, json(c(t, data)))
  res
end

const handlers = Dict{UTF8String, Function}()

handle(f, t) = handlers[t] = f

id = 0
const callbacks = Dict{Int,Condition}()

function rpc(t, data)
  i, c = (global id += 1), Condition()
  callbacks[i] = c
  data["callback"] = i
  msg(t, data)
  return wait(c)
end

function handlemsg(t, data)
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
end

isconnected() = sock ≠ nothing && isopen(sock)
