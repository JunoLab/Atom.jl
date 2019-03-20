using Juno
import JuliaInterpreter
using CodeTracking
using CodeTools
import Atom: basepath, handle

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
      :line => line,
      :isactive => isactive,
      :condition => condition
    )
  else
    return nothing
  end
end

handle("toggleBP") do file, line
  (file !== nothing && isfile(file)) || return [], "File not found."
  with_error_message() do
    removebreakpoint(file, line) || addbreakpoint(file, line)
    allbreakpoints()
  end
end

handle("getBreakpoints") do
  with_error_message() do
    allbreakpoints()
  end
end

handle("toggleException") do
  with_error_message() do
    if JuliaInterpreter.break_on_error[]
      JuliaInterpreter.break_off(:error)
    else
      JuliaInterpreter.break_on(:error)
    end
    return JuliaInterpreter.break_on_error[]
  end
end

handle("toggleUncaught") do
  return   Dict(
      :response => noting,
      :error => "Not supported yet."
    )
end

handle("clearbps") do
  with_error_message() do
    JuliaInterpreter.remove()
    allbreakpoints()
  end
end

handle("addArgs") do arg
  with_error_message() do
    bp = add_breakpoint_args(arg)
    bp isa Vector && isempty(bp) && error("""
      Invalid spec or no matching methods found. Please specify as `foo` or `foo(Bar, Baz)`, e.g.
      `sin` or `sin(Int)`. Make sure the function and all types can be reached from `Main`.
      """)
    allbreakpoints()
  end
end

handle("getbps") do
  with_error_message() do
    ret = []
    for (k, bp) in bps
      push!(ret, Dict(:view => render(Juno.Inline(), bp)))
    end
    ret
  end
end

handle("toggleAllActiveBP") do state
  with_error_message() do
    state ? JuliaInterpreter.disable() : JuliaInterpreter.enable()
    allbreakpoints()
  end
end

handle("toggleActiveBP") do file, line
  with_error_message() do
    toggleactive(file, line)
    allbreakpoints()
  end
end

function with_error_message(f)
  ret, err = nothing, false
  try
    ret = f()
  catch err
    err = sprint(showerror, err)
  end
  Dict(
    :response => ret,
    :error => err
  )
end

"""
    add_breakpoint_args(arg)

Takes a string of the form `foo` or `foo(Bar, Baz)` and sets a breakpoint for the appropriate methods.
"""
function add_breakpoint_args(arg)
  m = match(r"(.*?)(\(.*\))?$", arg)
  m === nothing && return
  if m[1] ≠ nothing
    if m[2] ≠ nothing
      fun = CodeTools.getthing(Main, m[1])
      args = Main.eval(Meta.parse("tuple$(m[2])"))
      meth = which(fun, args)
    else
      meth = CodeTools.getthing(Main, arg)
    end
  end
  JuliaInterpreter.breakpoint(meth)
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

function toggleactive(file, line)
  bps = JuliaInterpreter.breakpoints()
  for bp in bps
    bp_file, bp_line = location(bp)
    if normpath(bp_file) == normpath(file) && bp_line == line
      bp[].isactive ? JuliaInterpreter.disable(bp) : JuliaInterpreter.enable(bp)
    end
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

function no_chance_of_breaking()
  bps = JuliaInterpreter.breakpoints()
  !JuliaInterpreter.break_on_error[] && (isempty(bps) || all(bp -> !bp[].isactive, bps))
end
