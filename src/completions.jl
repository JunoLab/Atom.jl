# TODO: some caching, since this works poorly when there
# are lots of files around

import CodeTools: allcompletions, text

handle("completions") do data
  @destruct [pos = cursor(:cursor), code, path || nothing] = data
  mod = getmodule(data, pos)
  completions = allcompletions(code, pos, mod = mod, file = path)
  completions == nothing && return []
  completions = @>> completions filter(c->ismatch(r"^\w+$", text(c)))
  return completions
end
