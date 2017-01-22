using Juno
import Atom: basepath

const bps = Dict()

handle("clearbps") do
  for (k, bp) in bps
    Gallium.remove(bp)
    delete!(bps, k)
  end
end

Juno.@render Juno.Inline bp::Gallium.Breakpoint begin
  if isempty(bp.active_locations) && isempty(bp.inactive_locations) && isempty(bp.sources)
    Text("Empty Breakpoint.")
  else
    if !isempty(bp.sources)
      Juno.Row(Text("Breakpoint at "), Atom.baselink(string(bp.sources[1].fname), bp.sources[1].line))
    else
      sprint(show, bp)
    end
  end
end

handle("getbps") do
  ret = []
  for (k, bp) in bps
    push!(ret, Dict(:view => render(Juno.Inline(), bp)))
  end
  ret
end

handle("addsourcebp") do file, line
  # TODO: why the hash?
  k = hash((file, line))

  haskey(bps, k) && (return Dict(:msg => "ERR:bpalreadyexists"))

  contains(file, basepath("")) && (file = basename(file))
  bps[k] = Gallium.breakpoint(file, line)
  return Dict(:msg => "bpset")
end

handle("removesourcebp") do file, line
  k = hash((file, line))

  !haskey(bps, k) && (return Dict(:msg => "ERR:bpdoesnotexist"))

  Gallium.remove(bps[k])
  delete!(bps, k)
  return Dict(:msg => "bpremoved")
end

function breakpoint(args...)
  Gallium.breakpoint(args...)
  return
end
