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

function plotsize()
  info = @rpc plotsize()
  size = if info isa Array
    info
  elseif haskey(info, "size")
    info["size"]
  else
    [401, 501]
  end
  size .- 1
end

ploturl(url::String) = @msg ploturl(url)


const SELECTORS = Dict(
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
