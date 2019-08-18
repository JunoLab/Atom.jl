handle("completions") do data
  @destruct [path || nothing, mod || "Main", line, force] = data
  withpath(path) do
    m = getmodule′(mod)
    m = isa(m, Module) ? m : Main

    cs, pre = basecompletionadapter(line, m, force)

    d(:completions => cs,
      :prefix      => string(pre))
  end
end

using REPL.REPLCompletions

function basecompletionadapter(line, mod, force)
  comps, replace, shouldcomplete = try
    REPL.REPLCompletions.completions(line, lastindex(line), mod)
  catch err
    # might error when e.g. type inference fails
    [], 1:0, false
  end

  # Suppress completions if there are too many of them unless activated manually
  # @TODO: Checking whether `line` is a valid text to be completed in atom-julia-client
  #        in advance and drop this check
  (!force && length(comps) > 500) && begin
    comps = []
    replace = 1:0
  end

  pre = line[replace]
  d = []
  for c in comps
    # TODO: get local completions from CSTParser or similar
    # TODO: would be cool to provide `descriptionMoreURL` here to open the docpane
    if REPLCompletions.afterusing(line, first(replace))
      c isa REPLCompletions.PackageCompletion || continue
    end
    try
      push!(d, completion(mod, line, c))
    catch err
      continue
    end
  end
  d, pre
end

function completion(mod, line, c)
  return Dict(:type        => completiontype(line, c, mod),
              :rightLabel  => completionmodule(mod, c),
              :leftLabel   => returntype(mod, line, c),
              :text        => completiontext(c),
              :description => completionsummary(mod, c))
end

completiontext(x) = REPLCompletions.completion_text(x)
completiontext(x::REPLCompletions.PathCompletion) = rstrip(REPLCompletions.completion_text(x), '"')
completiontext(x::REPLCompletions.DictCompletion) = rstrip(REPLCompletions.completion_text(x), [']', '"'])
completiontext(x::REPLCompletions.MethodCompletion) = begin
  ct = REPLCompletions.completion_text(x)
  ct = match(r"^(.*) in .*$", ct)
  ct isa Nothing ? ct : ct[1]
end

returntype(mod, line, c) = ""
returntype(mod, line, c::REPLCompletions.MethodCompletion) = begin
  m = c.method
  atypes = m.sig
  sparams = m.sparam_syms
  wa = Core.Compiler.Params(typemax(UInt))  # world age
  inf = try
    Core.Compiler.typeinf_type(m, atypes, sparams, wa)
  catch err
    nothing
  end
  inf in (nothing, Any, Union{}) && return ""
  typ = string(inf)

  strlimit(typ, 20)
end
returntype(mod, line, c::REPLCompletions.PropertyCompletion) = begin
  prop = getproperty(c.value, c.property)
  typ = string(typeof(prop))
  strlimit(typ, 20)
end

using Base.Docs

function completionsummary(mod, c)
  ct = Symbol(REPLCompletions.completion_text(c))
  !cangetdocs(mod, ct) && return ""
  b = Docs.Binding(mod, ct)
  description(b)
end

function completionsummary(mod, c::REPLCompletions.ModuleCompletion)
  mod = c.parent
  word = c.mod
  !cangetdocs(mod, Symbol(word)) && return ""
  getdocs(string(mod), word) |> makedescription
end

function completionsummary(mod, c::REPLCompletions.MethodCompletion)
  ct = Symbol(c.func)
  !cangetdocs(mod, ct) && return ""
  b = Docs.Binding(mod, ct)
  description(b, Base.tuple_type_tail(c.method.sig))
end

function completionsummary(mod, c::REPLCompletions.KeywordCompletion)
  getdocs(string(mod), c.keyword) |> makedescription
end

function cangetdocs(m, s)
  Base.isbindingresolved(m, s) && !Base.isdeprecated(m, s)
end

function description(binding, sig = Union{})
  docs = try
    Docs.doc(binding, sig)
  catch err
    ""
  end
  makedescription(docs)
end

using Markdown

function makedescription(docs)
  docs isa Markdown.MD || return ""
  md = CodeTools.flatten(docs).content
  for part in md
    if part isa Markdown.Paragraph
      desc = Markdown.plain(part)
      occursin("No documentation found.", desc) && return ""
      return strlimit(desc, 200)
    end
  end
end

completionmodule(mod, c) = string(mod)
completionmodule(mod, c::REPLCompletions.ModuleCompletion) = string(c.parent)
completionmodule(mod, c::REPLCompletions.MethodCompletion) = string(c.method.module)
completionmodule(mod, c::REPLCompletions.KeywordCompletion) = "Base"

function completiontype(line, x, mod)
  ct = REPLCompletions.completion_text(x)
  startswith(ct, '@') && return "macro"
  startswith(ct, ':') && return "symbol"
  endswith(ct, '"') && return "macro"

  if x isa REPLCompletions.ModuleCompletion
    ct == "Vararg" && return ""
    t, f = try
      parsed = Meta.parse(ct, raise = false, depwarn = false)
      REPLCompletions.get_type(parsed, x.parent)
    catch e
      @error e
      nothing, false
    end

    if f
      return completiontype(t, x.parent, ct)
    end
  end
  x isa REPLCompletions.KeywordCompletion ? "keyword" :
    x isa REPLCompletions.PathCompletion ? "path" :
    x isa REPLCompletions.PackageCompletion ? "import" :
    x isa REPLCompletions.PropertyCompletion ? "property" :
    x isa REPLCompletions.FieldCompletion ? "attribute" :
    x isa REPLCompletions.MethodCompletion ? "method" :
    "object"
end

function completiontype(x, mod::Module, ct::AbstractString)
  x <: Module ? "module" :
    x <: DataType ? "type" :
    x isa Type{<:Type} ? "type" :
    typeof(x) == UnionAll ? "type" :
    x <: Function ? "function" :
    x <: Tuple ? "tuple" :
    isconst(mod, Symbol(ct)) ? "constant" :
    "object"
end

handle("cacheCompletions") do mod
  # m = getthing(mod)
  # m = isa(m, Module) ? m : Main
  # CodeTools.completions(m)
end
