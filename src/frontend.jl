selector(items) = @rpc select(items)

input() = @rpc input()

info(s) = @msg info(string(s))

# Provide our own readline implementation when readline(STDIN) is called.
# This is the same hack as the one used by IJulia.jl.
import Base.readline
function readline(io::Base.PipeEndpoint)
    if Juno.isactive() && io == STDIN
        Juno.input()
    else
        invoke(readline, Tuple{supertype(Base.PipeEndpoint)}, io)
    end
end

macro !(ex)
  quote
    result = $(esc(ex))
    display(span(c(render(Inline(), $(Expr(:quote, ex))),
                   " = ",
                   render(Inline(), result))))
    result
  end
end

# Blink stuff

type Shell <: AtomShell.Shell end

AtomShell.active(::Shell) = true

AtomShell.raw_window(::Shell, opts) =
  @rpc createWindow(merge(AtomShell.window_defaults, opts))

AtomShell.dot(::Shell, win::Integer, code; callback = true) =
  (callback ? rpc : msg)(:withWin, win, Blink.jsstring(code))

AtomShell.active(::Shell, win::Integer) = @rpc winActive(win)

plotsize() = @rpc plotsize()

ploturl(url::String) = @msg ploturl(url)

function blinkplot()
  p = Page()
  ploturl(Blink.localurl(p))
  return wait(p)
end
