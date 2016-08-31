selector(items) = @rpc select(items)

input() = @rpc input()

info(s) = @msg info(string(s))

"""
  progress(x = [0..1])

Set Atom's progress bar to the given value.
"""
progress(x::Void = nothing) = @msg progress(x)

progress(x::Real) =
  @msg progress(x < 0.01 ? nothing :
                x > 1 ? 1 :
                x)

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
