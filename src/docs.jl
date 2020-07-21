using DocSeeker
import Markdown

handle("searchdocs") do data
  @destruct [
    needle = query,
    mod || "Main",
    name_only = nameOnly || false,
    exportedonly = exportedOnly || false,
    allPackages || false
  ] = data
  return searchdocs′(
    needle,
    # kwargs to be passed to `DocSeeker.searchdocs`:
    # TODO: configuration for `maxreturns`
    !allPackages, mod, exportedonly, name_only
  )
end

function searchdocs′(needle, loaded = true, mod = "Main", exportedonly = false, name_only = false)
  searchmod = getmodule(mod)

  items, actualmod = _searchdocs(needle, loaded, searchmod, exportedonly, name_only)
  results = processdocs(items)

  # erase module input if the actual searched module has been changed
  push!(results, :shoulderase => searchmod ≠ actualmod)

  return results
end

function _searchdocs(needle, loaded = true, mod = Main, exportedonly = false, name_only = false)
  identifiers = split(needle, '.')
  head = string(identifiers[1])
  if loaded && head ≠ needle && (nextmod = getfield′(mod, head)) isa Module
    # if `head` is a module, update `needle` and `mod`
    nextneedle = join(identifiers[2:end], '.')
    return _searchdocs(nextneedle, loaded, nextmod, exportedonly, name_only)
  end

  return @errs(searchdocs(
    needle;
    loaded = loaded, mod = mod, exportedonly = exportedonly, name_only = name_only
  )), mod
end

function processdocs(items)
  return if items isa EvalError
    errstr = sprint(showerror, items.err)
    err = startswith(errstr, "Please regenerate the") ?
            """
            Please regenerate the documentation cache with the ↻ button above.
            Note that you need to add Docseeker.jl package in your environment (i.e. `] pkg> add DocSeeker`) in advance 
            and caching might take minutes. You can track the progress with the progress bar
            in the lower left corner, and should be able to use Juno normally during that time.
            """ : errstr
    Dict(
      :error => true,
      :errmsg => err
    )
  else
    Dict(
      :error => false,
      :items => [renderitem(i[2]) for i in items],
      :scores => [i[1] for i in items]
    )
  end
end

function renderitem(x)
  r = Dict(f => getfield(x, f) for f in fieldnames(DocSeeker.DocObj))
  r[:html] = view(renderMD(x.html))

  mod = getmodule(x.mod)
  name = Symbol(x.name)
  r[:typ], r[:icon], r[:nativetype] = if (name !== :ans || mod === Base) && iskeyword(name)
    "keyword", "k", x.typ
  else
    val = getfield′(mod, name)
    # @NOTE: DocSeeker can show docs for non-loaded packages via `createdocsdb()`
    nativetype = isundefined(val) ? "Undefined or not loaded yet" : x.typ
    wstype(mod, name, val), wsicon(mod, name, val), nativetype
  end
  r
end

handle("moduleinfo") do data
  @destruct [mod] = data
  moduleinfo(mod)
end

function moduleinfo(mod)
  d, items = getmoduleinfo(mod)
  items = [renderitem(i) for i in items]
  Dict(:doc => view(d), :items => items)
end

getmoduleinfo(mod) = ispackage(mod) ? packageinfo(mod) : modinfo(mod)
ispackage(mod) = Base.find_package(mod) ≠ nothing

function packageinfo(mod)
  path = DocSeeker.readmepath(mod)
  readme = ispath(path) ? String(read(path)) : ""
  description = Markdown.parse(Symbol(mod) ∈ stdlib_names ? "## Standard library package `$(mod)`" : readme)

  return  Hiccup.div(
            renderMD(description),
            renderMD("\n---\n## Defined symbols in `$(mod)`:")
          ), modulesymbols(mod)
end

function modinfo(mod)
  header = "## "
  header *= if mod in ("Core", "Base", "Main")
    "Toplevel module:"
  elseif first(split(mod, '.')) == "Core"
    "Core sub module:"
  elseif first(split(mod, '.')) == "Base"
    "Base sub module:"
  else
    "Module:"
  end
  header *= " `$(mod)`"
  header *= "\n---\n## Defined symbols:"

  return renderMD(header), modulesymbols(mod)
end

function modulesymbols(mod)
  syms = filter(x -> x.mod == mod, DocSeeker.alldocs())
  @inbounds sort!(syms, by = x -> x.name)[1:min(100,length(syms))]
end

using Logging: with_logger
using .Progress: JunoProgressLogger

function regeneratedocs()
  with_logger(JunoProgressLogger()) do
    @errs DocSeeker.createdocsdb()
  end
end
handle(regeneratedocs, "regeneratedocs")
