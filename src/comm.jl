macro msg(ex)
  @capture(ex, f_(args__)) || error("@msg requires function call syntax")
  :(msg($(string(f)), $(map(esc, args)...)))
end

macro rpc(ex)
  @capture(ex, f_(args__)) || error("@rpc requires function call syntax")
  :(rpc($(string(f)), $(map(esc, args)...)))
end

global sock = nothing

isactive(sock::Void) = false
isactive(sock) = isopen(sock)

macro ierrs(ex)
  :(try
      $(ex)
    catch e
      ee = EvalError(e, catch_backtrace())
      @msg error(d(:msg         => "Julia Client – Internal Error",
                   :detail      => sprint(showerror, e, ee.bt),
                   :dismissable => true))
      render(Console(), ee)
    end)
end

function initialise(; welcome = false)
  exit_on_sigint(false)
  eval(AtomShell, :(_shell = $(Shell())))
  welcome && @msg welcome()
end

function serve(port; kws...)
  server = listen(ip"127.0.0.1", port)
  print(STDERR, "juno-msg-ready")
  global sock = accept(server)
  @async while isopen(sock)
    @ierrs let
      msg = JSON.parse(sock)
      @schedule @ierrs handlemsg(msg...)
    end
  end
  initialise(; kws...)
end

function msg(t, args...)
  isactive(sock) || return
  println(sock, json(c(t, args...)))
end

const handlers = Dict{String, Function}()

handle(f, t) = handlers[t] = f

id = 0
const callbacks = Dict{Int,Condition}()

function rpc(t, args...)
  i, c = (global id += 1), Condition()
  callbacks[i] = c
  msg(d(:type => t, :callback => i), args...)
  return wait(c)
end

function handlemsg(t, args...)
  callback = nothing
  isa(t, Associative) && ((t, callback) = (t["type"], t["callback"]))
  if haskey(handlers, t)
    try
      result = handlers[t](args...)
      isa(callback, Integer) && msg("cb", callback, result)
    catch e
      isa(callback, Integer) && msg("cancelCallback", callback)
      rethrow()
    end
  else
    warn("Atom.jl: unrecognised message $t.")
    msg("cancelCallback", callback)
  end
end

handle("cb") do id, result
  notify(callbacks[id], result)
  delete!(callbacks, id)
end

isconnected() = sock ≠ nothing && isopen(sock)
