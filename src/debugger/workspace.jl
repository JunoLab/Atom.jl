using JuliaInterpreter: root, locals, moduleof, callee
import ..Atom: wsitem, handle

function contexts(state::DebuggerState = STATE)
  state.frame === nothing && return []
  ctx = []
  trace = ""
  frame = root(state.frame)
  active_callee = callee(active_frame(state))
  while frame ≠ nothing && frame ≠ active_callee
    trace = string(trace, "/", frame.framecode.scope isa Method ?
                                frame.framecode.scope.name : "top-level")
    c = Dict(:context => string("Debug: ", trace), :items => localvars(frame))
    pushfirst!(ctx, c)

    frame = frame.callee
  end
  ctx
end

function localvars(frame)
  vars = locals(frame)
  items = []
  mod = moduleof(frame)
  for v in vars
    # ref: https://github.com/JuliaDebug/JuliaInterpreter.jl/blob/master/src/utils.jl#L365-L370
    v.name == Symbol("#self#") && (isa(v.value, Type) || sizeof(v.value) == 0) && continue
    item = wsitem(mod, v.name, v.value)
    # Julia doesn't support "constantness" for local variables
    item[:type] == "constant" && (item[:type] = "variable")
    item[:icon] == "c" && (item[:icon] = "v")
    push!(items, item)
  end
  items
end
