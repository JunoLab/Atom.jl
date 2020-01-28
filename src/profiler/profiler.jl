module Profiler

using Profile, JSON, FlameGraphs

import ..Atom:  expandpath, @msg, handle

function tojson(node::FlameGraphs.Node, root = false)
  name, path = expandpath(string(node.data.sf.file))
  classes = []

  node.data.status & 0x01 ≠ 0 && push!(classes, "dynamic-dispatch")
  node.data.status & 0x02 ≠ 0 && push!(classes, "garbage-collection")

  Dict(
    :path => path,
    :location => name,
    :func => node.data.sf.func,
    :line => node.data.sf.line,
    :count => root ? sum(length(c.data.span) for c in node) : length(node.data.span),
    :classes => classes,
    :children => [tojson(c) for c in node]
  )
end

function profiler(data = Profile.fetch() ;kwargs...)
  graph = FlameGraphs.flamegraph(data ;kwargs...)
  graph === nothing && return
  pruneinternal!(graph)
  prunetask!(graph)
  @msg profile(tojson(graph, true))
end

function prunetask!(node)
  for c in node
    if (
          (
            c.data.sf.func == :task_done_hook &&
            endswith(string(c.data.sf.file), "task.jl")
          ) ||
          (
            # REPL
            c.data.sf.func == :eval &&
            FlameGraphs.isleaf(c) &&
            endswith(string(c.data.sf.file), "boot.jl")
          )
       )
      FlameGraphs.prunebranch!(c)
    end
  end
end

function pruneinternal!(node)
  for c in node
    if (
        (
          # REPL evaluation
          c.data.sf.func == :eval &&
          c.parent.data.sf.func == :repleval &&
          endswith(string(c.parent.data.sf.file), "repl.jl")
        ) ||
        (
          # inline evaluation
          c.data.sf.func == :include_string &&
          c.parent.data.sf.func == :include_string &&
          endswith(string(c.parent.parent.data.sf.file), "eval.jl")
        )
       )

      # Add children directly to the root node
      root = node
      replchild = c
      while !FlameGraphs.isroot(root)
          root = root.parent
          replchild = replchild.parent
      end
      FlameGraphs.graftchildren!(root, c)
      # Eliminate all nodes in between. This might include some that don't
      # call REPL code, but as this is also internal it seems OK.
      FlameGraphs.prunebranch!(replchild)
      return true
    else
      pruneinternal!(c) && return true
    end
  end
  return false
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
