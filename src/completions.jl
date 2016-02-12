matchesprefix(c::AString, pre::AString) = isempty(pre) || lowercase(c[1]) == lowercase(pre[1])
matchesprefix(c::Dict, pre::AString) = matchesprefix(c[:text], pre)
matchesprefix(c, ::Void) = true

handle("completions") do data
  @destruct [path || nothing, mod, line, column, force] = data
  withpath(path) do
    pre = CodeTools.prefix(line[1:column-1])
    pre = isempty(pre) ? nothing : pre[end]
    cs = CodeTools.completions(line[1:column-1], getthing(mod), default = false)
    cs == nothing && pre == nothing && !force && (cs = [])
    d(:completions => cs,
      :prefix      => pre,
      :mod         => mod)
  end
end

handle("cacheCompletions") do mod
  CodeTools.completions(getthing(mod))
end
