module Profiler

using Profile, JSON, FlameGraphs

import ..Atom:  expandpath, @msg, handle

function tojson(node::FlameGraphs.Node)
  name, path = expandpath(string(node.data.sf.file))
  classes = []

  node.data.status & 0x01 ≠ 0 && push!(classes, "isdispatch")
  node.data.status & 0x02 ≠ 0 && push!(classes, "isgc")
  
  Dict(
    :path => path,
    :location => name,
    :func => node.data.sf.func,
    :line => node.data.sf.line,
    :count => length(node.data.span),
    :classes => classes,
    :children => [tojson(c) for c in node]
  )
end

function profiler(data = Profile.fetch() ;kwargs...)
  graph = FlameGraphs.flamegraph(data ;kwargs...)
  graph === nothing && return
  @msg profile(tojson(graph))
end

handle("loadProfileTrace") do path
  if path === nothing
    return
  end

  json = try
    JSON.parse(String(open(read, first(path))))
  catch e
    @error "Error reading profile trace file at $path."
    nothing
  end
  json !== nothing && @msg profile(json)
end

handle("saveProfileTrace") do path, data
  if path === nothing
    return
  end

  try
    write(path, JSON.json(data))
  catch e
    @error "Error writing profile trace file at $path."
  end
end

end
