import CodeTools: allcompletions

handle("completions") do data
  pos = cursor(data["cursor"])
  mod = getmodule(data, pos)
  completions = allcompletions(data["code"], pos, mod = mod, file = get(data, "path", nothing))
  completions == nothing && return []
  completions = filter(c->ismatch(r"^\w+$", c), completions)
  return completions
end
