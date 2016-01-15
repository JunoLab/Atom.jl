select(items) = rpc("select", items)

type Shell <: AtomShell.Shell end

AtomShell.active(::Shell) = true

AtomShell.raw_window(::Shell, opts) =
  rpc("createWindow", merge(AtomShell.window_defaults, opts))

AtomShell.dot(::Shell, win::Integer, code; callback = true) =
  (callback ? rpc : msg)("withWin", win, Blink.jsstring(code))

AtomShell.active(::Shell, win::Integer) = rpc("winActive", win)
