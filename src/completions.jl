matchesprefix(c::AbstractString, pre::AbstractString) = isempty(pre) || lowercase(c[1]) == lowercase(pre[1])
matchesprefix(c::Dict, pre::AbstractString) = matchesprefix(c[:text], pre)
matchesprefix(c, ::Void) = true

handle("completions") do data
  @destruct [path || nothing, mod || "Main", line, force] = data
  withpath(path) do
    pre = CodeTools.prefix(line)
    pre = isempty(pre) ? nothing : pre[end]
    m = getthing(mod)
    m = isa(m, Module) ? m : Main
    cs = CodeTools.completions(line, m, default = false)
    cs == nothing && pre == nothing && !force && (cs = [])
    d(:completions => cs,
      :prefix      => pre,
      :mod         => mod)
  end
end

handle("cacheCompletions") do mod
  m = getthing(mod)
  m = isa(m, Module) ? m : Main
  CodeTools.completions(m)
end
