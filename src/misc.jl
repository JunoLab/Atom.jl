handle("ping") do
  "pong"
end

handle("args") do args
  append!(ARGS, args)
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

handle("enableplotpane") do enable
  enable ?
    Media.setdisplay(Media.Graphical, PlotPane()) :
    Media.unsetdisplay(Media.Graphical)
  nothing
end

handle("cancelCallback") do args...
  # TODO: Do something sensible here.
  # Until then it's better to silently fail than spam the REPL with "unrecognised
  # message" warnings.
end

handle("clear-workspace") do
  # has to be run by Main otherwise it throws an error
  eval(Main, :(workspace()))
end
