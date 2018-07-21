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

plotsize() = (@rpc plotsize()) .- 1

ploturl(url::String) = @msg ploturl(url)


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
    colors[k] = parse(UInt32, v, base=16)
  end
  colors
end
