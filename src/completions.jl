matchesprefix(c::AbstractString, pre::AbstractString) = isempty(pre) || lowercase(c[1]) == lowercase(pre[1])
matchesprefix(c::Dict, pre::AbstractString) = matchesprefix(c[:text], pre)
matchesprefix(c, ::Nothing) = true

handle("completions") do data
  @destruct [path || nothing, mod || "Main", line, force] = data
  withpath(path) do
    m = getthing(mod)
    m = isa(m, Module) ? m : Main

    cs, pre = basecompletionadapter(line, m)

    d(:completions => cs,
      :prefix      => string(pre),
      :mod         => string(mod))
  end
end

using REPL.REPLCompletions
function basecompletionadapter(line, mod)
  cs = REPL.REPLCompletions.completions(line, lastindex(line), mod)
  pre = line[cs[2]]
  d = []
  for c in cs[1]
    # TODO: get local completions from CSTParser or similar
    # TODO: would be cool to provide `descriptionMoreURL` here to open the docpane
    if REPLCompletions.afterusing(line, first(cs[2]))
      c isa REPLCompletions.PackageCompletion || continue
    end
    push!(d, completion(mod, line, c))
  end
  d, pre
end

function completion(mod, line, c)
  return Dict(:type => completiontype(line, c, mod),
              :rightLabel => completionmodule(mod, c),
              :leftLabel => returntype(mod, line, c),
              :text => completiontext(c),
              :description => completionsummary(mod, c))
end

completiontext(x) = REPLCompletions.completion_text(x)
completiontext(x::REPLCompletions.PathCompletion) = strip(REPLCompletions.completion_text(x), '"')
completiontext(x::REPLCompletions.DictCompletion) = strip(REPLCompletions.completion_text(x), ']')
function completiontext(x::REPLCompletions.MethodCompletion)
  ct = REPLCompletions.completion_text(x)
  ct = match(r"^(.*) in .*$", ct)
  ct isa Nothing ? ct : ct[1]
end

returntype(mod, line, c) = ""
function returntype(mod, line, c::REPLCompletions.MethodCompletion)
  m = c.method
  atypes = m.sig
  sparams = m.sparam_syms
  wa = Core.Compiler.Params(typemax(UInt))  # world age
  inf = Core.Compiler.typeinf_type(m, atypes, sparams, wa)
  typ = string(inf)
  typ == "Any" && return ""

  strlimit(typ, 20)
end

strlimit(str::AbstractString, limit = 30) = lastindex(str) > limit ?  str[1:prevind(str, limit)]*"…" : str

using Base.Docs
function completionsummary(mod, c)
  ct = REPLCompletions.completion_text(c)
  (!Base.isbindingresolved( mod, Symbol(ct)) || Base.isdeprecated(mod, Symbol(ct))) && return ""
  b = Docs.Binding(mod, Symbol(ct))
  description(b)
end

function completionsummary(mod, c::REPLCompletions.MethodCompletion)
  b = Docs.Binding(mod, Symbol(c.func))
  (!Base.isbindingresolved( mod, Symbol(c.func)) || Base.isdeprecated(mod, Symbol(c.func))) && return ""
  description(b, Base.tuple_type_tail(c.method.sig))
end

using Markdown
function description(binding, sig = Union{})
  docs = Docs.doc(binding, sig)
  docs isa Markdown.MD || return
  md = CodeTools.flatten(docs).content
  for part in md
    if part isa Markdown.Paragraph
      desc = Markdown.plain(part)
      occursin("No documentation found.", desc) && return ""
      return strlimit(desc, 100)
    end
  end
end

function completionmodule(mod, c)
  c isa REPLCompletions.ModuleCompletion ? string(c.parent) : string(mod)
end

function completiontype(line, x, mod)
  ct = REPLCompletions.completion_text(x)
  startswith(ct, '@') && return "macro"
  startswith(ct, ':') && return "symbol"
  endswith(ct, '"') && return "macro"

  if x isa REPLCompletions.ModuleCompletion
    ct == "Vararg" && return ""
    t, f = try
      parsed = Meta.parse(ct, raise=false, depwarn=false)
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
    ""
end

function completiontype(x, mod::Module, ct::AbstractString)
  x <: Module   ? "module"   :
  x <: DataType ? "type"     :
  x isa Type{<:Type} ? "type" :
  typeof(x) == UnionAll ? "type" :
  x <: Function ? "function" :
  x <: Tuple ? "tuple" :
  isconst(mod, Symbol(ct)) ? "constant" : ""
end

handle("cacheCompletions") do mod
  # m = getthing(mod)
  # m = isa(m, Module) ? m : Main
  # CodeTools.completions(m)
end
