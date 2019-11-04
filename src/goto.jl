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
    globalitems = globalgotoitems(word, getmodule(mod), path, text)
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
  # strip a dot-accessed module if exists
  identifiers = split(word, '.')
  head = string(identifiers[1])
  if head ≠ word && (nextmod = getfield′(mod, head)) isa Module
    # if `head` is a module, update `word` and `mod`
    nextword = join(identifiers[2:end], '.')
    return globalgotoitems(nextword, nextmod, text, path)
  end

  val = getfield′(mod, word)
  val isa Module && return [GotoItem(val)] # module goto

  items = toplevelgotoitems(word, mod, path, text)

  # append method gotos that are not caught by `toplevelgotoitems`
  ml = methods(val)
  files = map(item -> item.file, items)
  methoditems = filter!(item -> item.file ∉ files, methodgotoitems(ml))
  append!(items, methoditems)
end

## module goto

function GotoItem(mod::Module)
  file, line = mod == Main ? MAIN_MODULE_LOCATION[] : moduledefinition(mod)
  GotoItem(string(mod), file, line - 1)
end

## toplevel goto

const PathItemsMaps = Dict{String, Vector{ToplevelItem}}

"""
    Atom.SYMBOLSCACHE

"module" (`String`) ⟶ "path" (`String`) ⟶ "symbols" (`Vector{ToplevelItem}`) map

!!! note
    "module" should be canonical, i.e.: should be identical to names that are
      constructed from `string(mod::Module)`.
"""
const SYMBOLSCACHE = Dict{String, PathItemsMaps}()

function toplevelgotoitems(word, mod, path, text)
  key = string(mod)
  pathitemsmaps = if haskey(SYMBOLSCACHE, key)
    SYMBOLSCACHE[key]
  else
    SYMBOLSCACHE[key] = collecttoplevelitems(mod, path, text) # caching
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
function collecttoplevelitems(mod::Module, path::String, text::String)
  pathitemsmaps = PathItemsMaps()
  return if mod == Main || isuntitled(path)
    # for `Main` module and unsaved editors, always use CSTPraser-based approach
    # with a given buffer text, and don't check module validity
    _collecttoplevelitems!(nothing, path, text, pathitemsmaps)
  else
    _collecttoplevelitems!(mod, pathitemsmaps)
  end
end

# entry method when called from docpane/workspace
function collecttoplevelitems(mod::Module, path::Nothing, text::String)
  pathitemsmaps = PathItemsMaps()
  _collecttoplevelitems!(mod, pathitemsmaps)
end

# sub entry method
function _collecttoplevelitems!(mod::Module, pathitemsmaps::PathItemsMaps)
  entrypath, paths = modulefiles(mod)
  return if entrypath !== nothing # Revise-like approach
    _collecttoplevelitems!(stripdotprefixes(string(mod)), entrypath, paths, pathitemsmaps)
  else # if Revise-like approach fails, fallback to CSTParser-based approach
    entrypath, line = moduledefinition(mod)
    _collecttoplevelitems!(stripdotprefixes(string(mod)), entrypath, pathitemsmaps)
  end
end

# module-walk via Revise-like approach
function _collecttoplevelitems!(mod::Union{Nothing, String}, entrypath::String, paths::Vector{String}, pathitemsmaps::PathItemsMaps)
  # ignore toplevel items outside of `mod`
  items = toplevelitems(read(entrypath, String); mod = mod)
  push!(pathitemsmaps, entrypath => items)

  for path in paths
    # collect symbols in included files (always in `mod`)
    items = toplevelitems(read(path, String); mod = mod, inmod = true)
    push!(pathitemsmaps, path => items)
  end

  pathitemsmaps
end

# module-walk based on CSTParser, looking for toplevel `installed` calls
function _collecttoplevelitems!(mod::Union{Nothing, String}, entrypath::String, pathitemsmaps::PathItemsMaps; inmod = false)
  isfile′(entrypath) || return
  text = read(entrypath, String)
  _collecttoplevelitems!(mod, entrypath, text, pathitemsmaps; inmod = inmod)
end
function _collecttoplevelitems!(mod::Union{Nothing, String}, entrypath::String, text::String, pathitemsmaps::PathItemsMaps; inmod = false)
  items = toplevelitems(text; mod = mod, inmod = inmod)
  push!(pathitemsmaps, entrypath => items)

  # looking for toplevel `include` calls
  for item in items
    if item isa ToplevelCall
      expr = item.expr
      if isinclude(expr)
        nextfile = expr.args[3].val
        nextentrypath = joinpath(dirname(entrypath), nextfile)
        isfile′(nextentrypath) || continue
        # `nextentrypath` is always in `mod`
        _collecttoplevelitems!(mod, nextentrypath, pathitemsmaps; inmod = true)
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
function updatesymbols(mod, path::Nothing, text) end # fallback case
function updatesymbols(mod, path::String, text)
  m = getmodule(mod)

  # initialize the cache if there is no previous one
  if !haskey(SYMBOLSCACHE, mod)
    SYMBOLSCACHE[mod] = collecttoplevelitems(m, path, text)
  end

  # ignore toplevel items outside of `mod` when `path` is an entry file
  entrypath, _ = moduledefinition(m)
  inmod = path != entrypath
  items = toplevelitems(text; mod = stripdotprefixes(mod), inmod = inmod)
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

  for (i, mod) in enumerate(Base.loaded_modules_array())
    try
      key = string(mod)
      key == "__PackagePrecompilationStatementModule" && continue # will cause error

      @logmsg -1 "Symbols: $key ($i / $total)" progress=i/total _id=id
      SYMBOLSCACHE[key] = collecttoplevelitems(mod, nothing, "")
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
