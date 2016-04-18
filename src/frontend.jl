export selector, input, progress, @progress

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
progress(x = nothing) = @msg progress(x)

"""
  @progress for i = ...

Show a progress metre for the given loop.
"""
macro progress(ex)
  @capture(ex, for i_ in range_ body_ end) ||
    error("@progress requires a for loop")
    quote
      range = $(esc(range))
      i, n = 0, length(range)
      progress(0)
      for $(esc(i)) in range
        $(esc(body))
        i += 1
        progress(i/n)
      end
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
