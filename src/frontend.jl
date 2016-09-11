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

function progress(i, n, Δt, file)
  remaining = Δt/i*(n-i)
  h = Base.div(remaining, 60*60)
  m = Base.div(remaining -= h*60*60, 60)
  s = remaining - m*60
  t = @sprintf "%u:%02u:%02u" h m s

  prog = i/n < 0.1 ? "indeterminate" :
         i/n >   1 ?       1 :
         i/n

  msg("progress", i/n, "$t remaining @ $file", file)
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

ploturl(url::String) = @msg ploturl(url)

function blinkplot()
  p = Page()
  ploturl(Blink.localurl(p))
  return wait(p)
end
