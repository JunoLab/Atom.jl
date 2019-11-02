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
    mod, text,
  )
end

function gotosymbol(
  word, path = nothing,
  # local context
  column = 1, row = 1, startrow = 0, context = "", onlyglobal = false,
  # module context
  mod = "Main", text = ""
)
  try
    # local goto
    if !onlyglobal
      localitems = localgotoitem(word, path, column, row, startrow, context)
      isempty(localitems) || return Dict(
        :error => false,
        :items => todict.(localitems)
      )
    end

    # global goto
    globalitems = globalgotoitems(word, mod, path, text)
    isempty(globalitems) || return Dict(
      :error => false,
      :items => todict.(globalitems),
    )
  catch err
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

todict(gotoitem::GotoItem) = Dict(
  :text      => gotoitem.text,
  :file      => gotoitem.file,
  :line      => gotoitem.line,
  :secondary => gotoitem.secondary,
)

### local goto

function localgotoitem(word, path, column, row, startrow, context)
  word = first(split(word, '.')) # always ignore dot accessors
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
localgotoitem(word, ::Nothing, column, row, startrow, context) = [] # when called from docpane/workspace

### global goto - bundles toplevel gotos & method gotos

function globalgotoitems(word, mod, path, text)
  m = getmodule(mod)

  # strip a dot-accessed module if exists
  identifiers = split(word, '.')
  head = string(identifiers[1])
  if head ≠ word && getfield′(m, head) isa Module
    # if `head` is a module, update `word` and `mod`
    nextword = join(identifiers[2:end], '.')
    return globalgotoitems(nextword, head, text, path)
  end

  val = getfield′(m, word)
  val isa Module && return [GotoItem(val)] # module goto

  toplevelitems = toplevelgotoitems(word, mod, path, text)

  # append method gotos that are not caught by `toplevelgotoitems`
  ml = methods(val)
  files = map(item -> item.file, toplevelitems)
  methoditems = filter!(item -> item.file ∉ files, methodgotoitems(ml))
  append!(toplevelitems, methoditems)
end

## module goto

function GotoItem(mod::Module)
  file, line = mod == Main ? MAIN_MODULE_LOCATION[] : moduledefinition(mod)
  GotoItem(string(mod), file, line - 1)
end

## toplevel goto

const PathItemsMaps = Dict{String, Vector{ToplevelItem}}
const SYMBOLSCACHE = Dict{String, PathItemsMaps}()

function toplevelgotoitems(word, mod, path, text)
  pathitemsmaps = if haskey(SYMBOLSCACHE, mod)
    SYMBOLSCACHE[mod]
  else
    SYMBOLSCACHE[mod] = collecttoplevelitems(mod, path, text) # caching
  end

  ismacro(word) && (word = lstrip(word, '@'))
  ret = []
  for (path, items) in pathitemsmaps
    for item in filter(item -> filtertoplevelitem(word, item), items)
      push!(ret, GotoItem(path, item))
    end
  end
  return ret
end

# entry method
function collecttoplevelitems(mod::String, path::String, text::String)
  pathitemsmaps = PathItemsMaps()
  return if mod == "Main" || isuntitled(path)
    # for `Main` module and unsaved editors, always use CSTPraser-based approach
    # with a given buffer text
    _collecttoplevelitems!(mod, path, text, pathitemsmaps)
  else
    _collecttoplevelitems!(mod, pathitemsmaps)
  end
end

# entry method when called from docpane/workspace
function collecttoplevelitems(mod::String, path::Nothing, text::String)
  pathitemsmaps = PathItemsMaps()
  _collecttoplevelitems!(mod, pathitemsmaps)
end

# sub entry method
function _collecttoplevelitems!(mod::String, pathitemsmaps::PathItemsMaps)
  m = getmodule(mod)
  entrypath, paths = modulefiles(m)
  return if entrypath !== nothing # Revise-like approach
    _collecttoplevelitems!([entrypath; paths], pathitemsmaps)
  else # if Revise-like approach fails, fallback to CSTParser-based approach
    entrypath, line = moduledefinition(m)
    mod = string(last(split(mod, '.'))) # strip parent module prefixes e.g.: `"Main.Junk"`
    _collecttoplevelitems!(mod, entrypath, pathitemsmaps)
  end
end

# module-walk via Revise-like approach
function _collecttoplevelitems!(paths::Vector{String}, pathitemsmaps::PathItemsMaps)
  for path in paths
    text = read(path, String)
    parsed = CSTParser.parse(text, true)
    items = toplevelitems(parsed, text)
    push!(pathitemsmaps, path => items)
  end
  pathitemsmaps
end

# module-walk based on CSTParser, looking for toplevel `installed` calls
function _collecttoplevelitems!(mod::String, entrypath::String, pathitemsmaps::PathItemsMaps)
  isfile′(entrypath) || return
  text = read(entrypath, String)
  _collecttoplevelitems!(mod, entrypath, text, pathitemsmaps)
end
function _collecttoplevelitems!(mod::String, entrypath::String, text::String, pathitemsmaps::PathItemsMaps)
  parsed = CSTParser.parse(text, true)
  items = toplevelitems(parsed, text; mod = mod)
  push!(pathitemsmaps, entrypath => items)

  # looking for toplevel `include` calls
  for item in items
    if item isa ToplevelCall
      expr = item.expr
      if isinclude(expr)
        nextfile = expr.args[3].val
        nextentrypath = joinpath(dirname(entrypath), nextfile)
        isfile′(nextentrypath) || continue
        _collecttoplevelitems!(mod, nextentrypath, pathitemsmaps)
      end
    end
  end

  pathitemsmaps
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
  secondary = string(path, ":", line + 1)
  GotoItem(text, path, line, secondary)
end
function GotoItem(path::String, tupleh::ToplevelTupleH)
  expr = tupleh.expr
  text = str_value(expr)
  line = tupleh.lines.start - 1
  secondary = string(path, ":", line + 1)
  GotoItem(text, path, line, secondary)
end

## update toplevel symbols cache

# NOTE: handled by the `updateeditor` handler in outline.jl
function updatesymbols(items, mod, path::Nothing, text) end # fallback case
function updatesymbols(items, mod, path::String, text)
  # initialize the cache if there is no previous one
  if !haskey(SYMBOLSCACHE, mod)
    SYMBOLSCACHE[mod] = collecttoplevelitems(mod, path, text)
  end
  push!(SYMBOLSCACHE[mod], path => items)
end

## generate toplevel symbols cache

handle("regeneratesymbols") do
  with_logger(JunoProgressLogger()) do
    regeneratesymbols()
  end
  nothing
end

function regeneratesymbols()
  id = "regenerate_symbols_progress"
  @info "Generating symbols cache in loaded modules" progress=0 _id=id

  loaded = Set(string.(Base.loaded_modules_array()))
  pkgs = if isdefined(Pkg, :dependencies)
    getfield.(values(Pkg.dependencies()), :name)
  else
    collect(keys(Pkg.installed()))
  end
  unloaded = filter(pkg -> pkg ∉ loaded, pkgs)
  loadedlen = length(loaded)
  unloadedlen = length(unloaded)
  total = loadedlen + unloadedlen

  for (i, m) in enumerate(Base.loaded_modules_array())
    try
      mod = string(m)
      mod == "__PackagePrecompilationStatementModule" && continue # will cause error

      @logmsg -1 "Symbols: $mod ($i / $total)" progress=i/total _id=id
      SYMBOLSCACHE[mod] = collecttoplevelitems(mod, nothing, "")
    catch err
      @error err
    end
  end

  for (i, pkg) in enumerate(unloaded)
    try
      @logmsg -1 "Symbols: $pkg ($(i + loadedlen) / $total)" progress=(i+loadedlen)/total _id=id
      path = Base.find_package(pkg)
      SYMBOLSCACHE[pkg] = _collecttoplevelitems!(pkg, path, PathItemsMaps())
    catch err
      @error err
    end
  end

  @info "Finished generating the symbols cache" progress=1 _id=id
end

## clear toplevel symbols cache

handle("clearsymbols") do
  clearsymbols()
  nothing
end

function clearsymbols()
  for key in keys(SYMBOLSCACHE)
    delete!(SYMBOLSCACHE, key)
  end
end

## method goto

methodgotoitems(ml) = map(GotoItem, aggregatemethods(ml))

# aggregate methods with default arguments to the ones with full arguments
function aggregatemethods(ml)
  ms = collect(ml)
  sort!(ms, by = m -> m.nargs, rev = true)
  unique(m -> (m.file, m.line), ms)
end

function GotoItem(m::Method)
  _, link = view(m)
  sig = sprint(show, m)
  text = replace(sig, methodloc_regex => s"\g<sig>")
  file = link.file
  line = link.line - 1
  secondary = join(link.contents)
  GotoItem(text, file, line, secondary)
end
