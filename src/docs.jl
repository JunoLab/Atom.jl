using DocSeeker
import Markdown

handle("searchdocs") do data
  @destruct [mod || Main, nameOnly || false, exportedOnly || false, allPackages || false, query] = data
  items = @errs DocSeeker.searchdocs(query, mod = mod, exportedonly = exportedOnly,
                                     loaded = !allPackages, name_only = nameOnly)

  if items isa EvalError
    errstr = sprint(showerror, items.err)
    err = startswith(errstr, "Please regenerate the") ?
            """
            Please regenerate the documentation cache with the button above.
            Note that this might take a few minutes. You can track the progress with the progress bar
            in the lower left corner, and should be able to use Juno during normally during that time.
            """ : errstr
    Dict(
      :error => true,
      :errmsg => err
    )
  else
    Dict(
      :error => false,
      :items => [renderitem(i[2]) for i in items], :scores => [i[1] for i in items]
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
  d, items = getmoduleinfo(mod)
  items = [renderitem(i) for i in items]
  Dict(:doc => view(d), :items => items)
end

getmoduleinfo(mod) = ispackage(mod) ? packageinfo(mod) : moduleinfo(mod)
ispackage(mod) = Base.find_package(mod) ≠ nothing

function packageinfo(mod)
  path = DocSeeker.readmepath(mod)
  readme = ispath(path) ? String(read(path)) : ""
  description = Markdown.parse(mod ∈ values(Pkg.Types.stdlib()) ? "## Standard library package `$(mod)`" : readme)

  return  Hiccup.div(
            renderMD(description),
            renderMD("\n---\n## Defined symbols in `$(mod)`:")
          ), modulesymbols(mod)
end

function moduleinfo(mod)
  header = if mod ∈ ("Core", "Base", "Main") || first(split(mod, '.')) == "Base"
    "## Standard module `$(mod)`"
  else
    "## Module `$mod`"
  end * "\n---\n## Defined symbols:" |> renderMD

  header, modulesymbols(mod)
end

function modulesymbols(mod)
  syms = filter(x -> x.mod == mod, DocSeeker.alldocs())
  sort(syms, by = x -> x.name)[1:min(100, length(syms))]
end

using Logging: with_logger
using .Progress: JunoProgressLogger

handle("regeneratedocs") do
  with_logger(JunoProgressLogger()) do
    @errs DocSeeker.createdocsdb()
  end
end
