"""
    @msg(expression)

Calls `msg` with the name of the top-level function in `expression` as the first
argument and the arguments of that function as the remaining arguments. Note that
the toplevel function call will *not* be evaluated.

Example:
`@msg(sin(3))` will call `msg("sin", 3)`, i.e.
```
macroexpand(:(Atom.@msg(sin(3)))) == :((Atom.msg)("sin",3))
```
"""
macro msg(ex)
  @capture(ex, f_(args__)) || error("@msg requires function call syntax")
  :(msg($(string(f)), $(map(esc, args)...)))
end

"""
    @rpc(expression)

Calls `rpc` with the name of the top-level function in `expression` as the first
argument and the arguments of that function as the remaining arguments. Note that
the toplevel function call will *not* be evaluated.

Example:
`@rpc(sin(3))` will call `rpc("sin", 3)`, i.e.
```
macroexpand(:(Atom.@rpc(sin(3)))) == :((Atom.rpc)("sin",3))
```
"""
macro rpc(ex)
  @capture(ex, f_(args__)) || error("@rpc requires function call syntax")
  :(rpc($(string(f)), $(map(esc, args)...)))
end

"""
    sock

Socket over which the communication between server and client happens. Initialized
by `serve`.
"""
global sock = nothing

isactive(sock::Void) = false

"""
    isactive(sock)

Check whether the socked `sock` exists and is open.
"""
isactive(sock) = isopen(sock)

"""
    @ierrs(expression)

Catches errors internal to Atom.jl and renders them in the client.
"""
macro ierrs(ex)
  :(try
      $(esc(ex))
    catch e
      ee = EvalError(e, catch_stacktrace())
      Atom.msg("error", Dict(:msg         => "Julia Client – Internal Error",
                             :detail      => string(ee),
                             :dismissable => true))
      nothing
    end)
end

"""
    initialise(; welcome = false)

Sets up the environment for Atom.jl: Stop `SIGINT`s from killing Julia and send
a welcome message to Atom if `welcome == true`.
"""
function initialise(; welcome = false)
  Juno.isprecompiling() && return
  Juno.setactive!(true)
  exit_on_sigint(false)
  eval(AtomShell, :(_shell = $(Shell())))
  welcome && @msg welcome()
end

"""
    serve(port; kws...)

Start an asynchronous Julia server that listens on `localhost:port` and handle
the messages sent over that socket. The `kws...` are passed through to `initialise`.
"""
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

function connect(host, port; kws...)
  global sock = Base.connect(host, port)
  @async while isopen(sock)
    @ierrs let
      msg = JSON.parse(sock)
      @schedule @ierrs handlemsg(msg...)
    end
  end
  initialise(; kws...)
end

connect(port; kws...) = connect(ip"127.0.0.1", port; kws...)

"""
    msg(typ, args...)

Prints a json string to `sock` that contains all function arguments in an array.
"""
function msg(t, args...)
  isactive(sock) || return
  println(sock, json(c(t, args...)))
end

const handlers = Dict{String, Function}()

"""
    handle(func, typ)

Set the handler for messages of type `typ` to `func`.
"""
handle(f, t) = handlers[t] = f

id = 0
const callbacks = Dict{Int,Condition}()

"""
    rpc(typ, args...)

Sends a message to `sock` via `msg`. Blocks until the client returns a message
(which needs to send back the `callback` field).
"""
function rpc(t, args...)
  i, c = (global id += 1), Condition()
  callbacks[i] = c
  msg(d(:type => t, :callback => i), args...)
  return wait(c)
end

"""
    handlemsg(typ, args...)

Tries to call the message handler corresponding to `typ` (which can be set with
`handle`).
"""
function handlemsg(t, args...)
  callback = nothing
  isa(t, Associative) && ((t, callback) = (t["type"], t["callback"]))
  if haskey(handlers, t)
    try
      result = handlers[t](args...)
      isa(callback, Integer) && msg("cb", callback, result)
    catch e
      isa(callback, Integer) && msg("cancelCallback", callback, string(e))
      rethrow()
    end
  else
    warn("Atom.jl: unrecognised message $t.")
    callback ≠ nothing && msg("cancelCallback", callback)
  end
end

handle("cb") do id, result
  notify(callbacks[id], result)
  delete!(callbacks, id)
end

isconnected() = sock ≠ nothing && isopen(sock)
