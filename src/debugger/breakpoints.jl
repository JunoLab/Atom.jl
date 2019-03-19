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

function allbreakpoints()
  bps = JuliaInterpreter.breakpoints()
  filter!(x -> x ≠ nothing, simple_breakpoint.(bps))
end

function simple_breakpoint(bp::JuliaInterpreter.BreakpointRef)
  file, line = location(bp)
  isactive = bp[].isactive
  condition = bp[].condition
  condition = if condition == JuliaInterpreter.truecondition
    "true"
  elseif condition == JuliaInterpreter.falsecondition
    "false"
  else
    string(condition)
  end

  if file ≠ nothing
    shortpath, _ = Atom.expandpath(file)
    return Dict(
      :file => file,
      :shortpath => shortpath,
      :line => line - 1,
      :isactive => isactive,
      :condition => condition
    )
  else
    return nothing
  end
end

handle("toggleBP") do file, line
  removebreakpoint(file, line) || addbreakpoint(file, line)
  allbreakpoints()
end

function addbreakpoint(file, line)
  JuliaInterpreter.breakpoint(file, line)
end

function location(bp::JuliaInterpreter.BreakpointRef)
  if checkbounds(Bool, bp.framecode.breakpoints, bp.stmtidx)
      lineno = JuliaInterpreter.linenumber(bp.framecode, bp.stmtidx)
      whereis(bp.framecode.scope)[1], lineno
  else
      nothing, 0
  end
end

function removebreakpoint(file, line)
  bps = JuliaInterpreter.breakpoints()
  removed = false
  for bp in bps
    bp_file, bp_line = location(bp)
    if normpath(bp_file) == normpath(file) && bp_line == line
      JuliaInterpreter.remove(bp)
      removed = true
    end
  end
  removed
end

function breakpoint(args...)
  JuliaInterpreter.breakpoint(args...)
  return
end

function no_chance_of_breaking()
  bps = JuliaInterpreter.breakpoints()
  !JuliaInterpreter.break_on_error[] && (isempty(bps) || all(bp -> !bp[].isactive, bps))
end
