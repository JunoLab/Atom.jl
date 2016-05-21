export selector, input, progress, @progress, @!

"""
    selector([xs...]) -> x

Allow the user to select one of the `xs`.

`xs` should be an iterator of strings.
"""
selector(items) = @rpc select(items)

"""
    input() -> "..."

Prompt the user to input some text, and return it.
"""
input() = @rpc input()

"""
  progress(x = [0..1])

Set Atom's progress bar to the given value.
"""
progress(x::Void = nothing) = @msg progress(x)

progress(x::Real) =
  @msg progress(x < 0.01 ? nothing :
                x > 1 ? 1 :
                x)

"""
  @progress for i = ...

Show a progress metre for the given loop.
"""
macro progress(ex)
  @capture(ex, for x_ in range_ body_ end) ||
    error("@progress requires a for loop")
  @esc x range body
  quote
    range = $range
    n = length(range)
    for (i, $x) in enumerate(range)
      $body
      progress(i/n)
    end
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
