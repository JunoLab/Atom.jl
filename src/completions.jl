handle("completions") do data
  @destruct [mod, line, column] = data
  CodeTools.completions(line[1:column-1], getthing(mod))
end
