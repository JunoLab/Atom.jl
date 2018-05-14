selector(items) = @rpc select(items)

input() = @rpc input()

info(s) = @msg info(string(s))

sendnotify(s::AbstractString) = @msg notify(s)

macro !(ex)
  quote
    result = $(esc(ex))
    display(span(c(render(Inline(), $(Expr(:quote, ex))),
                   " = ",
                   render(Inline(), result))))
    result
  end
end

clearconsole() = @rpc clearconsole()

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

SELECTORS = Dict(
  "number" => ["syntax--constant", "syntax--numeric", "syntax--julia"],
  "symbol" => ["syntax--constant", "syntax--other", "syntax--symbol", "syntax--julia"],
  "string" => ["syntax--string", "syntax--quoted", "syntax--double", "syntax--julia"],
  "macro" => ["syntax--support", "syntax--function", "syntax--macro", "syntax--julia"],
  "keyword" => ["syntax--keyword", "syntax--control", "syntax--julia"],
  "funccall" => ["syntax--support", "syntax--function", "syntax--julia"],
  "funcdef" => ["syntax--entity", "syntax--name", "syntax--function"],
  "operator" => ["syntax--operator", "syntax--julia"],
  "comment" => ["syntax--comment", "syntax--julia"],
  "variable" => ["syntax--julia"],
  "type" => ["syntax--support", "syntax--type", "syntax--julia"]
)

function syntaxcolors(selectors = SELECTORS)
  colorsstr = @rpc syntaxcolors(selectors)
  colors = Dict{String, UInt32}()
  for (k, v) in colorsstr
    colors[k] = parse(UInt32, v, 16)
  end
  colors
end
