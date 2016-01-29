handle("ping") do
  "pong"
end

handle("echo") do data
  data
end

handle("cd") do path
  cd(path)
end
