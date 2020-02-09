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
  name::String
  text::String
  file::String
  line::Int

  GotoItem(name::String, text::String, file::String, line::Int = 0) =
    new(name, text, normpath(file), line)
end
GotoItem(name::String, file::String, line::Int = 0) = GotoItem(name, name, file, line)

# for messaging over julia ⟷ Atom
todict(gotoitem::GotoItem) = Dict(
  :text      => gotoitem.text,
  :file      => gotoitem.file,
  :line      => gotoitem.line,
  :secondary => string(gotoitem.file, ':', gotoitem.line + 1),
)

### local goto

function localgotoitem(word, path, column, row, startrow, context)
  word = first(split(word, '.')) # always ignore dot accessors
  position = row - startrow
  ls = locals(context, position, column)
  filter!(l -> l.name == word && l.line < position, ls)
  return map(ls) do l # there should be zero or one element in `ls`
    name = l.name
    line = startrow + l.line - 1
    GotoItem(name, path, line)
  end
end
localgotoitem(word, ::Nothing, column, row, startrow, context) = GotoItem[] # when called from docpane/workspace

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
  name = string(mod)
  file, line = mod == Main ? MAIN_MODULE_LOCATION[] : moduledefinition(mod)
  GotoItem(name, file, line - 1)
end

## toplevel goto

const PathItemsMap = Dict{String, Vector{GotoItem}}

# NOTE:
# this data structure should only keep "simple" data so that it doesn't eat
# too much memory when the cache has got fat (like via `regeneratesymbols`)
# TODO?:
# maybe we will end up creating a more generic struct that represents a "symbol",
# and wanting `SYMBOLSCACHE` to store them instead of `GotoItem`
# (should be kept "simple" atst though, and ideally it handles both toplevel and local symbols)
# so that we can use `SYMBOLSCACHE` as a general cache interface for various static features
# like goto, find references, and so on.

"""
    Atom.SYMBOLSCACHE

"module" (`String`) ⟶ "path" (`String`) ⟶ "symbols" (`Vector{GotoItem}`) map.

!!! note
    "module" should be canonical, i.e.: should be identical to names that are
      constructed from `string(mod::Module)`.
"""
const SYMBOLSCACHE = Dict{String, PathItemsMap}()

function toplevelgotoitems(word, mod, path, text)
  key = string(mod)
  pathitemsmap = if haskey(SYMBOLSCACHE, key)
    SYMBOLSCACHE[key]
  else
    SYMBOLSCACHE[key] = collecttoplevelitems(mod, path, text) # caching
  end

  ret = []
  for (_, items) in pathitemsmap
    @>> filter(let name = word
      item -> name == item.name
    end, items) append!(ret)
  end
  ret
end

# entry methods
function collecttoplevelitems(mod::Module, path::String, text::String)
  return if mod == Main || isuntitled(path)
    # for `Main` module and unsaved editors, always use CSTPraser-based approach
    # with a given buffer text, and don't check module validity
    __collecttoplevelitems(nothing, path, text)
  else
    _collecttoplevelitems(mod)
  end
end
# when `path === nothing`, e.g.: called from docpane/workspace
collecttoplevelitems(mod::Module, path::Nothing, text::String) = _collecttoplevelitems(mod)

function _collecttoplevelitems(mod::Module)
  entrypath, paths = modulefiles(mod)
  return if entrypath !== nothing # Revise-like approach
    __collecttoplevelitems(stripdotprefixes(string(mod)), [entrypath; paths])
  else # if Revise-like approach fails, fallback to CSTParser-based approach
    entrypath, line = moduledefinition(mod)
    __collecttoplevelitems(stripdotprefixes(string(mod)), entrypath)
  end
end

# module-walk via Revise-like approach
function __collecttoplevelitems(mod::Union{Nothing, String}, paths::Vector{String})
  pathitemsmap = PathItemsMap()

  entrypath, paths = paths[1], paths[2:end]

  # ignore toplevel items outside of `mod`
  items = toplevelitems(read(entrypath, String); mod = mod)
  pathitemsmap[entrypath] = GotoItem.(entrypath, items)

  # collect symbols in included files (always in `mod`)
  for path in paths
    items = toplevelitems(read(path, String); mod = mod, inmod = true)
    pathitemsmap[path] = GotoItem.(path, items)
  end

  return pathitemsmap
end

# module-walk based on CSTParser, looking for toplevel `included` calls
function __collecttoplevelitems(mod::Union{Nothing, String}, entrypath::String, pathitemsmap::PathItemsMap = PathItemsMap(); inmod = false)
  isfile′(entrypath) || return pathitemsmap
  # escape recursive `include` loops
  entrypath in keys(pathitemsmap) && return pathitemsmap
  text = read(entrypath, String)
  __collecttoplevelitems(mod, entrypath, text, pathitemsmap; inmod = inmod)
end
function __collecttoplevelitems(mod::Union{Nothing, String}, entrypath::String, text::String, pathitemsmap::PathItemsMap = PathItemsMap(); inmod = false)
  items = toplevelitems(text; mod = mod, inmod = inmod)
  pathitemsmap[entrypath] = GotoItem.(entrypath, items)

  # looking for toplevel `include` calls
  for item in items
    if item isa ToplevelCall
      expr = item.expr
      if isinclude(expr)
        nextfile = expr.args[3].val
        nextentrypath = joinpath(dirname(entrypath), nextfile)
        isfile′(nextentrypath) || continue
        # `nextentrypath` is always in `mod`
        __collecttoplevelitems(mod, nextentrypath, pathitemsmap; inmod = true)
      end
    end
  end

  return pathitemsmap
end

GotoItem(path::String, item::ToplevelItem) = GotoItem("", path) # fallback case
function GotoItem(path::String, binding::ToplevelBinding)
  expr = binding.expr
  bind = binding.bind
  name = CSTParser.defines_macro(expr) ? string('@', bind.name) : bind.name
  text = CSTParser.has_sig(expr) ? str_value(CSTParser.get_sig(expr)) : name
  line = binding.lines.start - 1
  GotoItem(name, text, path, line)
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
  push!(SYMBOLSCACHE[mod], path => GotoItem.(path, items))
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
      SYMBOLSCACHE[key] = _collecttoplevelitems(mod)
    catch err
      @error err
    end
  end

  for (i, pkg) in enumerate(unloaded)
    try
      @logmsg -1 "Symbols: $pkg ($(i + loadedlen) / $total)" progress=(i+loadedlen)/total _id=id
      path = Base.find_package(pkg)
      SYMBOLSCACHE[pkg] = __collecttoplevelitems(pkg, path)
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

methodgotoitems(ml) = GotoItem.(aggregatemethods(ml))

# aggregate methods with default arguments to the ones with full arguments
function aggregatemethods(ml)
  ms = collect(ml)
  sort!(ms, by = m -> m.nargs, rev = true)
  unique(m -> (m.file, m.line), ms)
end

function GotoItem(m::Method)
  text = replace(sprint(show, m), methodloc_regex => s"\g<sig>")
  _, link = view(m)
  file = link.file
  line = link.line - 1
  GotoItem(text, file, line)
end
