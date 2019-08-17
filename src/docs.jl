using DocSeeker
import Markdown

handle("searchdocs") do data
  @destruct [mod || Main, nameOnly || false, exportedOnly || false, allPackages || false, query] = data
  items = @errs DocSeeker.searchdocs(query, mod = mod, exportedonly = exportedOnly,
                                     loaded = !allPackages, name_only = nameOnly)
  items isa EvalError ?
    Dict(:error => true, :errmsg => sprint(showerror, items.err)) :
    Dict(:error => false, :items => [renderitem(i[2]) for i in items], :scores => [i[1] for i in items])
end

function renderitem(x)
  r = Dict(f => getfield(x, f) for f in fieldnames(DocSeeker.DocObj))
  r[:html] = view(renderMD(x.html))
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
  description = Markdown.parse(mod ∈ values(Pkg.Types.stdlib()) ? "## Julia Standard Library `$(mod)`" : readme)

  return  Hiccup.div(
            renderMD(description),
            renderMD("### Defined symbols:")
          ), modulesymbols(mod)
end

function moduleinfo(mod)
  header = if mod == "Core"
    "## Julia `Core`"
  elseif first(split(mod, '.')) == "Base"
    "## Julia `Base` Library: `$(last(split(mod, '.')))`"
  else
    "## Module `$mod`"
  end |> str -> str * "\n### Defined symbols:" |> renderMD

  header, modulesymbols(mod)
end

function modulesymbols(mod)
  syms = filter(x -> x.mod == mod, DocSeeker.alldocs())
  sort(syms, by = x -> x.name)[1:min(100, length(syms))]
end

handle("regenerateCache") do
  DocSeeker.createdocsdb()
end
