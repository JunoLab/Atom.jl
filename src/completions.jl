matchesprefix(c::AString, pre::AString) = isempty(pre) || lowercase(c[1]) == lowercase(pre[1])
matchesprefix(c::Dict, pre::AString) = matchesprefix(c[:text], pre)
matchesprefix(c, ::Void) = true

handle("completions") do data
  @destruct [mod, line, column] = data
  pre = CodeTools.prefix(line[1:column-1])
  pre = isempty(pre) ? nothing : pre[end]
  cs = CodeTools.completions(line[1:column-1], getthing(mod))
  filter!(c -> matchesprefix(c, pre), cs)
  d(:completions => cs,
    :prefix      => pre)
end
