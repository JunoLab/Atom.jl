using Juno
import JuliaInterpreter
using CodeTracking
using CodeTools
import Atom: basepath, handle

const _breakpoints = Dict{Int, Any}()
const _conditions = Dict{Any, Any}()

"""
    allbreakpoints()

Updates internal `_breakpoints` dictionary and returns all breakpoints in a vector of dictionaries.
"""
function allbreakpoints()
  bps = JuliaInterpreter.breakpoints()
  simple_bps = []
  empty!(_breakpoints)
  id = 1

  for (bp, cond) in _conditions
    bp in bps && continue
    delete!(_conditions, bp)
  end

  for bp in bps
    sbp = simple_breakpoint(bp, id = id)
    if sbp === nothing
      @warn "Not good. Weird breakpoint encountered."
    end
    _breakpoints[id] = bp
    push!(simple_bps, sbp)
    id += 1
  end

  simple_bps
end

function simple_breakpoint(bp::JuliaInterpreter.BreakpointRef; id = nothing)
  file, line = location(bp)
  isactive = bp[].isactive
  condition = bp[].condition
  condition = if condition == JuliaInterpreter.truecondition || condition == JuliaInterpreter.falsecondition
    nothing
  else
    get(_conditions, bp, "?")
  end

  if file ≠ nothing
    shortpath, _ = Atom.expandpath(file)
    return Dict(
      :file => file,
      :shortpath => shortpath,
      :line => line,
      :isactive => isactive,
      :condition => condition,
      :id => id
    )
  else
    return nothing
  end
end

handle("toggleBP") do item
  with_error_message() do
    if haskey(item, "id") && item["id"] ≠ nothing
      id = item["id"]
      if haskey(_breakpoints, id)
        JuliaInterpreter.remove(_breakpoints[id])
      else
        error("Inconsistent internal state.")
      end
    else
      haskey(item, "file") && haskey(item, "line") || return [], "File must be saved."
      file, line = item["file"], item["line"]
      (file !== nothing && isfile(file)) || return [], "File not found."
      removebreakpoint(file, line) || addbreakpoint(file, line)

    end
    allbreakpoints()
  end
end

handle("getBreakpoints") do
  with_error_message() do
    Dict(
      :breakpoints => allbreakpoints(),
      :onException => JuliaInterpreter.break_on_error[],
      :onUncaught => false
    )

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

handle("toggleActiveBP") do item
  with_error_message() do
    if haskey(item, "id") && item["id"] ≠ nothing
      id = item["id"]
      if haskey(_breakpoints, id)
        bp = _breakpoints[id]
        bp[].isactive ? JuliaInterpreter.disable(bp) : JuliaInterpreter.enable(bp)
      else
        error("Inconsistent internal state.")
      end
    else
      file, line = item["file"], item["line"]
      toggleactive(file, line)
    end
    allbreakpoints()
  end
end

handle("addConditionById") do item, cond
  with_error_message() do
    if haskey(item, "id") && item["id"] ≠ nothing
      id = item["id"]
      if haskey(_breakpoints, id)
        bp = _breakpoints[id]
        framecode = bp.framecode
        stmtidx = bp.stmtidx

        expr = Meta.parse(cond)
        if !(expr isa JuliaInterpreter.Condition)
          error("Breakpoint condition must be an expression or a tuple of a module and an expression.")
        end
        JuliaInterpreter.remove(bp)
        bp = JuliaInterpreter.breakpoint!(framecode, stmtidx, expr)
        _conditions[bp] = cond
      else
        error("Inconsistent Internal State. Abort abort aboooort!")
      end
    else
      error("Inconsistent Internal State. Abort abort aboooort!")
    end

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
      bps = filter(bp->bp[].isactive, JuliaInterpreter.breakpoints())

      # work around https://github.com/timholy/CodeTracking.jl/issues/27
      for bp in bps
          JuliaInterpreter.disable(bp)
      end
      ret = whereis(bp.framecode.scope)[1], lineno
      for bp in bps
          JuliaInterpreter.enable(bp)
      end

      ret
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
