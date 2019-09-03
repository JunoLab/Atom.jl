using Juno
import JuliaInterpreter
using CodeTracking
using CodeTools
import Atom: basepath, handle

const _breakpoints = Dict{Int, Any}()
const _conditions = Dict{Any, Any}()

const _compiledMode = Ref{Any}(JuliaInterpreter.finish_and_return!)

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

  for bp in filter!(bp -> bp isa JuliaInterpreter.BreakpointSignature, bps)
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

function simple_breakpoint(bp::JuliaInterpreter.BreakpointSignature; id = id)
  io = IOBuffer()
  print(io, bp.f)
  if bp.sig !== nothing
    print(io, '(', join("::" .* string.(bp.sig.types), ", "), ')')
  end
  description = String(take!(io))
  file, line = "", 0
  if bp.f isa Method
    _, _, file, line = Base.arg_decl_parts(bp.f)
    file = Atom.basepath(string(file))
    description = replace(description, r" in .* at .*$" => "")
  end

  condition = bp.condition === nothing ? nothing : get(_conditions, bp, "?")

  return Dict(
    :file => file,
    :line => line,
    :description => description,
    :isactive => bp.enabled[],
    :condition => condition,
    :id => id
  )
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
      error("We have a problem, Houston.")
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
        bp isa JuliaInterpreter.BreakpointSignature || error("Wrong breakpoint type encountered.")

        func = bp.f
        sig = bp.sig
        line = bp.line

        expr = Meta.parse(cond)
        if !(expr isa JuliaInterpreter.Condition)
          error("Breakpoint condition must be an expression or a tuple of a module and an expression.")
        end
        JuliaInterpreter.remove(bp)
        bp = JuliaInterpreter.breakpoint(func, sig, line, expr)
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

handle("getBreakpoints") do
  with_error_message() do
    Dict(
      :breakpoints => allbreakpoints(),
      :onException => JuliaInterpreter.break_on_error[],
      :onUncaught => false
    )
  end
end

isCompileMode() = _compiledMode[] === JuliaInterpreter.Compiled()

handle("toggleCompiled") do
  with_error_message() do
    _compiledMode[] = (isCompileMode() ?
      (_compiledMode[] = JuliaInterpreter.finish_and_return!) :
      (_compiledMode[] = JuliaInterpreter.Compiled()))
    return isCompileMode()
  end
end

handle("toggleException") do
  with_error_message() do
    if JuliaInterpreter.break_on_throw[]
      JuliaInterpreter.break_off(:throw)
    else
      JuliaInterpreter.break_on(:throw)
    end
    return JuliaInterpreter.break_on_throw[]
  end
end

handle("toggleUncaught") do
  with_error_message() do
    if JuliaInterpreter.break_on_error[]
      JuliaInterpreter.break_off(:error)
    else
      JuliaInterpreter.break_on(:error)
    end
    return JuliaInterpreter.break_on_error[]
  end
end

handle("clearbps") do
  with_error_message() do
    JuliaInterpreter.remove()
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
        bp.enabled[] ? JuliaInterpreter.disable(bp) : JuliaInterpreter.enable(bp)
      else
        error("Inconsistent internal state.")
      end
    else
      error("I'm broken.")
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

function no_chance_of_breaking()
  bps = JuliaInterpreter.breakpoints()
  !JuliaInterpreter.break_on_error[] && (isempty(bps) || all(bp -> !bp[].isactive, bps))
end
