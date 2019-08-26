handle("completions") do data
  @destruct [path || nothing, mod || "Main", line, force] = data
  withpath(path) do
    m = getmodule′(mod)

    cs, pre = basecompletionadapter(line, m, force)

    d(:completions => cs,
      :prefix      => string(pre))
  end
end

using REPL.REPLCompletions

function basecompletionadapter(line, mod, force)
  comps, replace, shouldcomplete = try
    completions(line, lastindex(line), mod)
  catch err
    # might error when e.g. type inference fails
    [], 1:0, false
  end

  # Suppress completions if there are too many of them unless activated manually
  # @TODO: Checking whether `line` is a valid text to be completed in atom-julia-client
  #        in advance and drop this check
  (!force && length(comps) > MAX_COMPLETIONS) && begin
    comps = []
    replace = 1:0
  end

  pre = line[replace]
  d = []
  for c in comps
    # TODO: get local completions from CSTParser or similar
    # TODO: would be cool to provide `descriptionMoreURL` here to open the docpane
    if REPLCompletions.afterusing(line, first(replace))
      (c isa REPLCompletions.PackageCompletion ||
       (c isa REPLCompletions.ModuleCompletion && getfield′′(mod, Symbol(c.mod)) isa Module)
      ) || continue
    end
    try
      push!(d, completion(mod, line, c))
    catch err
      continue
    end
  end
  d, pre
end

const MAX_COMPLETIONS = 500

function completion(mod, line, c)
  return Dict(:type        => completiontype(line, c, mod),
              :icon        => completionicon(c),
              :rightLabel  => completionmodule(mod, c),
              :leftLabel   => returntype(mod, line, c),
              :text        => completiontext(c),
              :description => completionsummary(mod, c))
end

completiontext(x) = completion_text(x)
completiontext(x::REPLCompletions.PathCompletion) = rstrip(completion_text(x), '"')
completiontext(x::REPLCompletions.DictCompletion) = rstrip(completion_text(x), [']', '"'])
completiontext(x::REPLCompletions.MethodCompletion) = begin
  ct = completion_text(x)
  ct = match(r"^(.*) in .*$", ct)
  ct isa Nothing ? ct : ct[1]
end

using JuliaInterpreter: sparam_syms

returntype(mod, line, c) = ""
returntype(mod, line, c::REPLCompletions.MethodCompletion) = begin
  m = c.method
  atypes = m.sig
  sparams = Core.svec(sparam_syms(m)...)
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
returntype(mod, line, ::REPLCompletions.PathCompletion) = "Path"

using Base.Docs

completionsummary(mod, c) = begin
  ct = Symbol(completion_text(c))
  !cangetdocs(mod, ct) && return ""
  b = Docs.Binding(mod, ct)
  description(b)
end
completionsummary(mod, c::REPLCompletions.ModuleCompletion) = begin
  mod = c.parent
  word = c.mod
  !cangetdocs(mod, Symbol(word)) && return ""
  getdocs(string(mod), word) |> makedescription
end
completionsummary(mod, c::REPLCompletions.MethodCompletion) = begin
  ct = Symbol(c.func)
  !cangetdocs(mod, ct) && return ""
  b = Docs.Binding(mod, ct)
  description(b, Base.tuple_type_tail(c.method.sig))
end
completionsummary(mod, c::REPLCompletions.KeywordCompletion) = begin
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
completionmodule(mod, ::REPLCompletions.KeywordCompletion) = "Base"
completionmodule(mod, ::REPLCompletions.PathCompletion) = ""

completiontype(line, c, mod) = begin
  ct = completion_text(c)
  ismacro(ct) && return "snippet"
  startswith(ct, ':') && return "tag"

  if c isa REPLCompletions.ModuleCompletion
    ct == "Vararg" && return ""
    mod = c.parent
    val, found = try
      parsed = Meta.parse(ct, raise = false, depwarn = false)
      REPLCompletions.get_value(parsed, mod)
    catch e
      @error e
      nothing, false
    end
    return found ? completiontype(val, mod, ct) : "ignored"
  end
  c isa REPLCompletions.KeywordCompletion ? "keyword" :
    c isa REPLCompletions.PathCompletion ? "path" :
    c isa REPLCompletions.PackageCompletion ? "import" :
    c isa REPLCompletions.PropertyCompletion ? "property" :
    c isa REPLCompletions.FieldCompletion ? "attribute" :
    c isa REPLCompletions.MethodCompletion ? "method" :
    "variable"
end
completiontype(val, mod::Module, ct::AbstractString) = wstype(mod, Symbol(ct), val)
completiontype(line, ::REPLCompletions.DictCompletion, mod) = "key" # fallen into "macro" otherwise

ismacro(ct::AbstractString) = startswith(ct, '@') || endswith(ct, '"')

completionicon(c) = ""
completionicon(c::REPLCompletions.ModuleCompletion) = begin
  ismacro(c.mod) && return "icon-mention"
  mod = c.parent
  name = Symbol(c.mod)
  val = getfield′′(mod, name)
  wsicon(mod, name, val)
end
completionicon(::REPLCompletions.PathCompletion) = "icon-file"

handle("cacheCompletions") do mod
  # m = getthing(mod)
  # m = isa(m, Module) ? m : Main
  # CodeTools.completions(m)
end
