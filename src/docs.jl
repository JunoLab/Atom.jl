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

handle("regenerateCache") do
  DocSeeker.createdocsdb()
end

function ispackage(mod)
  for f in readdir(Pkg.dir())
    f == mod && return true
  end
  return false
end

function modulesymbols(mod)
  syms = filter(x -> x.mod == mod, DocSeeker.alldocs())
  sort(syms, by = x -> x.name)[1:min(100, length(syms))]
end

function packageinfo(mod)
  Hiccup.div(
    renderMD(Markdown.parse(String(read(DocSeeker.readmepath(mod))))),
    Hiccup.Node(:hr),
    Hiccup.h2("defined symbols:")
  ), modulesymbols(mod)
end

function moduleinfo(mod)
  header = if mod == "Core"
    renderMD("## Julia `Core`")
  elseif first(split(mod, '.')) == "Base"
    renderMD("## Julia Standard Library: `$mod`")
  else
    renderMD("## Module `$mod`")
  end

  header, modulesymbols(mod)
end

getmoduleinfo(mod) = ispackage(mod) ? packageinfo(mod) : moduleinfo(mod)
