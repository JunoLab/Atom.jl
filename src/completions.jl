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
    push!(d, Dict{Any, Any}(:type => completiontype(line, cs[2], c, mod),
                  :description => nothing,
                  :rightLabel => completionmodule(mod, c),
                  :text => string(REPLCompletions.completion_text(c)),
                  :displayText => nothing))
  end
  d, pre
end

function completionmodule(mod, c)
  c isa REPLCompletions.ModuleCompletion ? string(c.parent) : string(mod)
end

function completiontype(line, inds, x, mod)
  if x isa REPLCompletions.ModuleCompletion
    t, f = try
      str = string(line[1:(first(inds)-1)], REPLCompletions.completion_text(x))
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
    " "
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
