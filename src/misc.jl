using Pkg

handle("ping") do
  "pong"
end

handle("args") do args
  if length(filter!(!isempty, args)) !== 0
    append!(Base.ARGS, args)
  end
end

handle("echo") do data
  data
end

handle("cd") do path
  hideprompt() do
    cd(path)
    @info "Changed working directory to `$path`"
  end
end

handle("activateProject") do dir
  hideprompt() do
    Pkg.activate(dir)
  end
  update_project()
end

handle("activateParentProject") do dir
  hideprompt() do
    if (path = search_up_file("Project.toml", dir)) === nothing
      @warn "No project file found for `$dir`"
      return
    end
    Pkg.activate(path)
  end
  update_project()
end

handle("activateDefaultProject") do
  hideprompt() do
    Pkg.activate()
  end
  update_project()
end

handle("evalsimple") do code
  Core.eval(Main, Meta.parse(code))
end

handle("exit") do
  exit()
end

handle("packages") do
  finddevpackages()
end

const PlotPaneEnabled = Ref(true)

handle("enableplotpane") do enable
  if enable
    Media.setdisplay(Media.Graphical, PlotPane())
    PlotPaneEnabled[] = true
  else
    Media.unsetdisplay(Media.Graphical)
    PlotPaneEnabled[] = false
  end
  nothing
end

handle("cancelCallback") do args...
  # TODO: Do something sensible here.
  # Until then it's better to silently fail than spam the REPL with "unrecognised
  # message" warnings.
end

using Pkg: status
handle("reportinfo") do
  io = IOBuffer()
  versioninfo(io)
  println(io)
  println(io, project_status())
  String(take!(io))
end
