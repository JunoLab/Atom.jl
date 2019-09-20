using REPL
using REPL.LineEdit
using REPL.REPLCompletions
using JuliaInterpreter: moduleof, locals, eval_code
import ..Atom: @msg

const normal_prefix = Sys.iswindows() ? "\e[33m" : "\e[38;5;166m"
const compiled_prefix = "\e[96m"

function debugprompt()
  try
    panel = REPL.LineEdit.Prompt("debug> ";
              prompt_prefix = isCompileMode() ? compiled_prefix : normal_prefix,
              prompt_suffix = Base.text_colors[:normal],
              complete = JunoDebuggerRPELCompletionProvider(),
              on_enter = s -> true)

    panel.hist = REPL.REPLHistoryProvider(Dict{Symbol,Any}(:junodebug => panel))
    REPL.history_reset_state(panel.hist)

    search_prompt, skeymap = LineEdit.setup_search_keymap(panel.hist)
    search_prompt.complete = REPL.LatexCompletions()

    panel.on_done = (s, buf, ok) -> begin
      if !ok
        LineEdit.transition(s, :abort)
        REPL.LineEdit.reset_state(s)
        return false
      end
      @msg working()

      line = String(take!(buf))

      if isempty(line)
        @msg doneWorking()
        return true
      end

      try
        r = interpret(line)
        r ≠ nothing && display(r)
      catch err
        display_error(stderr, err, stacktrace(catch_backtrace()))
      end
      println()
      LineEdit.reset_state(s)

      @msg doneWorking()
      @msg updateWorkspace()

      return true
    end

    panel.keymap_dict = LineEdit.keymap(Dict{Any,Any}[skeymap, LineEdit.history_keymap, LineEdit.default_keymap, LineEdit.escape_defaults])

    REPL.run_interface(Base.active_repl.t, REPL.LineEdit.ModalInterface([panel, search_prompt]))
  catch e
    @msg doneWorking()
    @msg updateWorkspace()
    e isa InterruptException || rethrow(e)
  end
end

# completions

struct JunoDebuggerRPELCompletionProvider <: REPL.CompletionProvider end

function LineEdit.complete_line(c::JunoDebuggerRPELCompletionProvider, s, state::DebuggerState = STATE)
  partial = REPL.beforecursor(s.input_buffer)
  full = LineEdit.input_string(s)

  frame = active_frame(state)

  # module-aware repl backend completions
  comps, range, should_complete = REPLCompletions.completions(full, lastindex(partial), moduleof(frame))
  ret = map(REPLCompletions.completion_text, comps)

  # local completions -- should be shown first
  @>> locals(frame) filter!(v -> begin
    # ref: https://github.com/JuliaDebug/JuliaInterpreter.jl/blob/master/src/utils.jl#L365-L370
    if v.name == Symbol("#self") && (v.value isa Type || sizeof(v.value) == 0)
      return false
    else
      return startswith(string(v.name), partial)
    end
  end) map(v -> string(v.name)) prepend!(ret) unique!

  return ret, partial[range], should_complete
end

# Evaluation
function interpret(code::AbstractString, state::DebuggerState = STATE)
  state.frame === nothing && return
  eval_code(active_frame(state), code)
end
