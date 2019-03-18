using Juno
import JuliaInterpreter
using CodeTracking
import Atom: basepath, handle

handle("clearbps") do
  JuliaInterpreter.remove()
end

# Juno.@render Juno.Inline bp::Gallium.Breakpoint begin
#   if isempty(bp.active_locations) && isempty(bp.inactive_locations) && isempty(bp.sources)
#     Text("Empty Breakpoint.")
#   else
#     if !isempty(bp.sources)
#       Juno.Row(Text("Breakpoint at "), Atom.baselink(string(bp.sources[1].fname), bp.sources[1].line))
#     else
#       sprint(show, bp)
#     end
#   end
# end

handle("getbps") do
  ret = []
  for (k, bp) in bps
    push!(ret, Dict(:view => render(Juno.Inline(), bp)))
  end
  ret
end

normbase(file) = contains(file, basepath("")) ? basename(file) : file

handle("addsourcebp") do file, line
  JuliaInterpreter.breakpoint(file, line)
  return true
end

function location(bp::JuliaInterpreter.BreakpointRef)
  if checkbounds(Bool, bp.framecode.breakpoints, bp.stmtidx)
      lineno = JuliaInterpreter.linenumber(bp.framecode, bp.stmtidx)
      whereis(bp.framecode.scope)[1], lineno
  else
      @warn "not a source BP"
  end
end

handle("removesourcebp") do file, line
  bps = JuliaInterpreter.breakpoints()
  for bp in bps
    bp_file, bp_line = location(bp)
    if normpath(bp_file) == normpath(file) && bp_line == line
      JuliaInterpreter.remove(bp)
    end
  end
  return true
end

function breakpoint(args...)
  JuliaInterpreter.breakpoint(args...)
  return
end

function no_chance_of_breaking()
  bps = JuliaInterpreter.breakpoints()
  !JuliaInterpreter.break_on_error[] && (isempty(bps) || all(bp -> !bp[].isactive, bps))
end
