export selector, input

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

type Shell <: AtomShell.Shell end

AtomShell.active(::Shell) = true

AtomShell.raw_window(::Shell, opts) =
  @rpc createWindow(merge(AtomShell.window_defaults, opts))

AtomShell.dot(::Shell, win::Integer, code; callback = true) =
  (callback ? rpc : msg)(:withWin, win, Blink.jsstring(code))

AtomShell.active(::Shell, win::Integer) = @rpc winActive(win)
