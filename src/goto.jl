using CSTParser

handle("gotosymbol") do data
  @destruct [
    word,
    path || nothing,
    # local context
    column || 1,
    row || 1,
    startRow || 0,
    context || "",
    onlyGlobal || true,
    # module context
    mod || "Main",
    text || "",
  ] = data
  gotosymbol(
    word, path,
    column, row, startRow, context, onlyGlobal,
    mod, text
  )
end

function gotosymbol(
  word, path = nothing,
  column = 1, row = 1, startrow = 0, context = "", onlyglobal = false,
  mod = "Main", text = ""
)
  try
    # local goto
    if !onlyglobal
      localitems = localgotoitem(word, path, column, row, startrow, context)
      isempty(localitems) || return Dict(
        :error => false,
        :items => map(Dict, localitems),
      )
    end

    # global goto
    globalitems = globalgotoitems(word, mod, text, path)
    isempty(globalitems) || return Dict(
      :error => false,
      :items => map(Dict, globalitems),
    )
  catch err
    @error err
    return Dict(:error => true)
  end

  return Dict(:error => true) # nothing hits
end

struct GotoItem
  text::String
  file::String
  line::Int
  secondary::String
  GotoItem(text, file, line = 0, secondary = "") = new(text, normpath(file), line, secondary)
end
Dict(gotoitem::GotoItem) = Dict(
  :text      => gotoitem.text,
  :file      => gotoitem.file,
  :line      => gotoitem.line,
  :secondary => gotoitem.secondary,
)

### local goto

function localgotoitem(word, path, column, row, startrow, context)
  word = first(split(word, '.')) # ignore dot accessors
  position = row - startrow
  ls = locals(context, position, column)
  filter!(ls) do l
    l[:name] == word &&
    l[:line] < position
  end
  map(ls) do l # there should be zero or one element in `ls`
    text = l[:name]
    line = startrow + l[:line] - 1
    GotoItem(text, path, line)
  end
end
localgotoitem(word, ::Nothing, column, row, startrow, context) = [] # when `path` is not destructured

### global goto - bundles toplevel gotos & method gotos

function globalgotoitems(word, mod, text, path)
  toplevelitems = toplevelgotoitems(word, mod, text, path)
  files = map(item -> item.file, toplevelitems)
  # only append methods that are not caught by `toplevelgotoitems`
  methoditems = filter!(methodgotoitems(mod, word)) do item
    item.file ∉ files
  end
  append!(toplevelitems, methoditems)
end

## toplevel goto

const PathItemsMaps = Dict{String, Vector{ToplevelItem}}
const SYMBOLSCACHE = Dict{String, PathItemsMaps}()

function toplevelgotoitems(word, mod, text, path)
  pathitemsmaps = if haskey(SYMBOLSCACHE, mod)
    SYMBOLSCACHE[mod]
  else
    SYMBOLSCACHE[mod] = searchtoplevelitems(getmodule(mod), text, path) # caching
  end

  ismacro(word) && (word = lstrip(word, '@'))
  ret = Vector{GotoItem}()
  for (path, items) ∈ pathitemsmaps
    for item ∈ filter(item -> filtertoplevelitem(word, item), items)
      push!(ret, GotoItem(path, item))
    end
  end
  return ret
end

# entry method
function searchtoplevelitems(mod::Module, text::String, path::String)
  pathitemsmaps = PathItemsMaps()
  if mod == Main # for `Main` module, always use the passed text
    _searchtoplevelitems(text, path, pathitemsmaps)
  else
    _searchtoplevelitems(mod, pathitemsmaps)
  end
  return pathitemsmaps
end

# entry method when path is not deconstructured, e.g.: called from docpane/workspace
function searchtoplevelitems(mod::Module, text::String, path::Nothing)
  pathitemsmaps = PathItemsMaps()
  _searchtoplevelitems(mod, pathitemsmaps)
  return pathitemsmaps
end

# sub entry method
function _searchtoplevelitems(mod::Module, pathitemsmaps::PathItemsMaps)
  entrypath, paths = modulefiles(mod)
  if entrypath !== nothing # when Revise approach succeeds, just find items in those files
    for p ∈ [entrypath; paths]
      _searchtoplevelitems(p, pathitemsmaps)
    end
  else # if Revise approach fails, fallback to parser-based module walk
    path = parentfile(mod)
    text = read(path, String)
    _searchtoplevelitems(text, path, pathitemsmaps)
  end
end

# module walk based on Revise approach
function _searchtoplevelitems(path::String, pathitemsmaps::PathItemsMaps)
  text = read(path, String)
  parsed = CSTParser.parse(text, true)
  items = toplevelitems(parsed, text)
  pathitemsmap = path => items
  push!(pathitemsmaps, pathitemsmap)
end

# parser-based module walk via looking for toplevel `installed` calls
function _searchtoplevelitems(text::String, path::String, pathitemsmaps::PathItemsMaps)
  parsed = CSTParser.parse(text, true)
  items = toplevelitems(parsed, text)
  pathitemsmap = path => items
  push!(pathitemsmaps, pathitemsmap)

  # looking for toplevel `installed` calls
  for item in items
    if item isa ToplevelCall
      expr = item.expr
      if isinclude(expr)
        nextfile = expr.args[3].val
        nextpath = joinpath(dirname(path), nextfile)
        isfile(nextpath) || continue
        text = read(nextpath, String)
        _searchtoplevelitems(text, nextpath, pathitemsmaps)
      end
    end
  end
end

filtertoplevelitem(word, item::ToplevelItem) = false
function filtertoplevelitem(word, bind::ToplevelBinding)
  bind = bind.bind
  bind === nothing ? false : word == bind.name
end
function filtertoplevelitem(word, tupleh::ToplevelTupleH)
  expr = tupleh.expr
  for arg in expr.args
    if str_value(arg) == word
      return true
    end
  end
  return false
end

function GotoItem(path::String, bind::ToplevelBinding)
  expr = bind.expr
  text = bind.bind.name
  if CSTParser.has_sig(expr)
    sig = CSTParser.get_sig(expr)
    text = str_value(sig)
  end
  line = bind.lines.start - 1
  secondary = path * ":" * string(line)
  GotoItem(text, path, line, secondary)
end
function GotoItem(path::String, tupleh::ToplevelTupleH)
  expr = tupleh.expr
  text = str_value(expr)
  line = tupleh.lines.start - 1
  secondary = path * ":" * string(line)
  GotoItem(text, path, line, secondary)
end

## update toplevel symbols

handle("updatesymbols") do data
  @destruct [
    mod || "Main",
    text || "",
    path || "untitled"
  ] = data
  try
    updatesymbols(mod, text, path)
  catch err
  end
  return nothing
end

function updatesymbols(mod, text, path = "untitled")
  if haskey(SYMBOLSCACHE, mod)
    parsed = CSTParser.parse(text, true)
    items = toplevelitems(parsed, text)
    push!(SYMBOLSCACHE[mod], path => items)
  else
    # initialize the cache if there is no cache
    SYMBOLSCACHE[mod] = searchtoplevelitems(getmodule(mod), text, path)
  end
end

## generate toplevel symbols
handle("regeneratesymbols") do
  with_logger(JunoProgressLogger()) do
    regeneratesymbols()
  end
end

function regeneratesymbols()
  id = "regenerate_symbols_progress"
  @info "Start regenerating symbols cache" progress=0 _id=id

  loaded = Set(string.(Base.loaded_modules_array()))
  unloaded = filter!(collect(keys(Pkg.installed()))) do pkg
    pkg ∉ loaded
  end
  loadedlen = length(loaded)
  unloadedlen = length(unloaded)
  total = loadedlen + unloadedlen

  for (i, mod) ∈ enumerate(Base.loaded_modules_array())
    try
      modstr = string(mod)
      modstr == "__PackagePrecompilationStatementModule" && continue # will cause error
      pathitemsmap = PathItemsMaps()

      @info "Symbols: $modstr ($i / $total)" progress=i/total _id=id
      _searchtoplevelitems(mod, pathitemsmap)
      SYMBOLSCACHE[modstr] = pathitemsmap
    catch err
      @error err
    end
  end

  for (i, pkg) ∈ enumerate(unloaded)
    try
      path = Base.find_package(pkg)
      text = read(path, String)
      pathitemsmap = PathItemsMaps()

      @info "Symbols: $pkg ($(i + loadedlen) / $total)" progress=(i+loadedlen)/total _id=id
      _searchtoplevelitems(text, path, pathitemsmap)
      SYMBOLSCACHE[pkg] = pathitemsmap
    catch err
      @error err
    end
  end

  @info "Finish symbols cache generation" progress=1 _id=id
end

## method goto

function methodgotoitems(mod, word)::Vector{GotoItem}
  ms = @errs getmethods(mod, word)
  if ms isa EvalError
    []
  else
    map(GotoItem, aggregatemethods(ms))
  end
end

# aggregate methods with default arguments to the ones with full arguments
aggregatemethods(f) = aggregatemethods(methods(f))
aggregatemethods(ms::MethodList) = aggregatemethods(collect(ms))
function aggregatemethods(ms::Vector{Method})
  ms = sort(ms, by = m -> m.nargs, rev = true)
  unique(m -> (m.file, m.line), ms)
end

function GotoItem(m::Method)
  _, link = view(m)
  sig = sprint(show, m)
  text = replace(sig, r" in .* at .*$" => "")
  file = link.file
  line = link.line - 1
  secondary = join(link.contents)
  GotoItem(text, file, line, secondary)
end
