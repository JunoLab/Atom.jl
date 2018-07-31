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
    push!(d, completion(mod, line, c))
  end
  d, pre
end

function completion(mod, line, c)
  return Dict(:type => completiontype(line, c, mod),
              :description => nothing,
              :rightLabel => completionmodule(mod, c),
              :leftLabel => returntype(mod, line, c),
              :text => completiontext(c),
              :description => completionsummary(mod, c))
end

completiontext(x) = REPLCompletions.completion_text(x)
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

  strlimit(string(inf), 20)
end

strlimit(str::AbstractString, limit = 30) = lastindex(str) > limit ?  str[1:prevind(str, limit)]*"…" : str

using Base.Docs
function completionsummary(mod, c)
  ct = REPLCompletions.completion_text(c)
  b = Docs.Binding(mod, Symbol(ct))
  CodeTools.description(b)
end

function completionsummary(mod, c::REPLCompletions.MethodCompletion)
function completionmodule(mod, c)
  c isa REPLCompletions.ModuleCompletion ? string(c.parent) : string(mod)
end

function completiontype(line, x, mod)
  ct = REPLCompletions.completion_text(x)
  startswith(ct, '@') && return "macro"

  if x isa REPLCompletions.ModuleCompletion
    t, f = try
      str = string(line[1:(first(inds)-1)], ct)
      REPLCompletions.get_type(Meta.parse(str, raise=false, depwarn=false), mod)
    catch e
      nothing, false
    end

    f && return completiontype(t)
  end
  x isa REPLCompletions.KeywordCompletion ? "keyword" :
    x isa REPLCompletions.PathCompletion ? "path" :
    x isa REPLCompletions.PackageCompletion ? "module" :
    x isa REPLCompletions.PropertyCompletion ? "property" :
    x isa REPLCompletions.FieldCompletion ? "field" :
    x isa REPLCompletions.MethodCompletion ? "λ" :
    "v"
end

function completiontype(x)
  x <: Module   ? "module" :
  x <: DataType ? "type"   :
  x <: Function ? "λ"      :
                  "constant"
end

handle("cacheCompletions") do mod
  m = getthing(mod)
  m = isa(m, Module) ? m : Main
  CodeTools.completions(m)
end
