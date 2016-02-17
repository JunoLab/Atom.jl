handle("ping") do
  "pong"
end

handle("echo") do data
  data
end

handle("cd") do path
  cd(path)
end

handle("evalsimple") do code
  eval(parse(code))
end

handle("exit") do
  exit()
end
