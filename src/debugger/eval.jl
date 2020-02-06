using Atom: undefined

function interpret(code::AbstractString, state::DebuggerState = STATE)
  state.frame === nothing && return
  eval_code(active_frame(state), code)
end

# if returned value is `Atom.undefined`, this means `code` shouldn't be evaluated within this frame
function interpret_string(code, path, line, state::DebuggerState = STATE)
  # frame validation
  state.frame === nothing && return undefined

  frame = state.frame
  scope = frame.framecode.scope

  # only work for methods
  scope isa Module && return undefined

  # path identity check
  path != fullpath(getfile(frame)) && return undefined

  # line number check
  defstr, startline = definition(String, scope)
  endline = startline + sum(c === '\n' for c in defstr)
  startline <= line <= endline || return undefined

  return interpret(code, state)
end
