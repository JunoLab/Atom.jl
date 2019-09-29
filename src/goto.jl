#=
@TODO: remove dot accessor within local bindings
=#

handle("goto") do data
  @destruct [
    word,
    path || "",
    mod || "Main",
    column || 1,
    row || 1,
    startRow || 0,
    context || "",
    refreshFiles || [],
    onlytoplevel || false
  ] = data
  goto(word, mod, path, column, row, startRow, context, refreshFiles, onlytoplevel)
end

function goto(word, mod, path, column = 1, row = 1, startRow = 0, context = "", refreshfiles = [], onlytoplevel = false)
  mod = getmodule(mod)

  # local items
  if !onlytoplevel
    localitems = localgotoitem(word, path, column, row, startRow, context)
    isempty(localitems) || return Dict(
      :error => false,
      :items => localitems,
      :remainingfiles => refreshfiles
    )
  end

  # toplevel items
  toplevelitems = toplevelgotoitem(mod, word, path, refreshfiles)
  isempty(toplevelitems) || return Dict(
    :error => false,
    :items => toplevelitems,
    :remainingfiles => refreshfiles
  )

  # method goto
  methodgotoitems = methodgotoitem(mod, word)
  isempty(methodgotoitems) || return Dict(
    :error => false,
    :items => methodgotoitems,
    :remainingfiles => refreshfiles
  )

  Dict(:error => true) # nothing hits
end

## local goto

function localgotoitem(word, path, column, row, startRow, context)
  position = row - startRow
  ls = locals(context, position, column)
  filter!(ls) do l
    l[:name] == word &&
    l[:line] < position
  end
  map(ls) do l # there should be zero or one element in `ls`
    text = l[:name]
    line = startRow + l[:line] - 1
    gotoitem(text, path, line)
  end
end

function gotoitem(text, file, line = 0, secondary = "")
  Dict(
    :text      => text,
    :file      => file,
    :line      => line,
    :secondary => secondary
  )
end

## toplevel goto

function toplevelgotoitem(mod, word, path, refreshfiles)
  entrypath = Base.find_package(string(mod))
  entrypath === nothing && (entrypath = path) # for e.g.: Base modules

  itempathmaps = searchtoplevelitems(entrypath, refreshfiles)

  ismacro(word) && (word = lstrip(word, '@'))
  filter!(itempathmap -> filtertoplevelitem(itempathmap, word), itempathmaps)
  map(gotoitem, itempathmaps)
end

const symbolscache = Dict{String, Vector{ToplevelItem}}()

function searchtoplevelitems(path, refreshfiles, itempathmaps = [])
  ind = findfirst(p -> p == path, refreshfiles)
  currentitems = if haskey(symbolscache, path) && ind === nothing
    symbolscache[path]
  else
    text = read(path, String)
    parsed = CSTParser.parse(text, true)
    items = toplevelitems(parsed, text)
    symbolscache[path] = items
    ind !== nothing && deleteat!(refreshfiles, ind)
    items
  end

  append!(itempathmaps, map(item -> (item, path), currentitems))

  for item in currentitems
    if item isa ToplevelCall
      expr = item.expr
      if isinclude(expr)
        nextfile = expr.args[3].val
        nextpath = joinpath(dirname(path), nextfile)
        searchtoplevelitems(nextpath, refreshfiles, itempathmaps)
      end
    end
  end

  itempathmaps
end

filtertoplevelitem(itempathmap, word) = false
function filtertoplevelitem(bindpathmap::Tuple{ToplevelBinding, String}, word)
  bind = bindpathmap[1].bind
  bind === nothing ? false : word == bind.name
end
function filtertoplevelitem(tuplehpathmap::Tuple{ToplevelTupleH, String}, word)
  expr = tuplehpathmap[1].expr
  for arg in expr.args
    if str_value(arg) == word
      return true
    end
  end
  return false
end

function gotoitem(bindpathmap::Tuple{ToplevelBinding, String})
  bind = bindpathmap[1]
  expr = bind.expr
  text = bind.bind.name
  if CSTParser.has_sig(expr)
    sig = CSTParser.get_sig(expr)
    text = str_value(sig)
  end
  file = bindpathmap[2]
  line = bind.lines.start - 1
  secondary = file * ":" * string(line)
  gotoitem(text, file, line, secondary)
end
function gotoitem(tuplehpathmap::Tuple{ToplevelTupleH, String})
  tupleh = tuplehpathmap[1]
  expr = tupleh.expr
  text = str_value(expr)
  file = tuplehpathmap[2]
  line = tupleh.lines.start - 1
  secondary = file * ":" * string(line)
  gotoitem(text, file, line, secondary)
end

## method goto

function methodgotoitem(mod, word)
  ms = @errs getmethods(mod, word)
  if ms isa EvalError
    []
  else
    map(gotoitem, aggregatemethods(ms))
  end
end

# aggregate methods with default arguments to the ones with full arguments
aggregatemethods(f) = aggregatemethods(methods(f))
aggregatemethods(ms::MethodList) = aggregatemethods(collect(ms))
function aggregatemethods(ms::Vector{Method})
  ms = sort(ms, by = m -> m.nargs, rev = true)
  unique(m -> (m.file, m.line), ms)
end

function gotoitem(m::Method)
  _, link = view(m)
  sig = sprint(show, m)
  text = replace(sig, r" in .* at .*$" => "")
  file = link.file
  line = link.line - 1
  secondary = join(link.contents)
  gotoitem(text, file, line, secondary)
end
