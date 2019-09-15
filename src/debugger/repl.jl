using REPL
using REPL.LineEdit
using REPL.REPLCompletions

const normal_prefix = Sys.iswindows() ? "\e[33m" : "\e[38;5;166m"
const compiled_prefix = "\e[96m"

function debugprompt()
  try
    panel = REPL.LineEdit.Prompt("debug> ";
              prompt_prefix = isCompileMode() ? compiled_prefix : normal_prefix,
              prompt_suffix = Base.text_colors[:normal],
              complete = DebugCompletionProvider(),
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
      Atom.msg("working")

      line = String(take!(buf))

      isempty(line) && return true

      try
        r = Atom.JunoDebugger.interpret(line)
        r ≠ nothing && display(r)
      catch err
        display_error(stderr, err, stacktrace(catch_backtrace()))
      end
      println()
      LineEdit.reset_state(s)

      Atom.msg("doneWorking")
      Atom.msg("updateWorkspace")

      return true
    end

    panel.keymap_dict = LineEdit.keymap(Dict{Any,Any}[skeymap, LineEdit.history_keymap, LineEdit.default_keymap, LineEdit.escape_defaults])

    REPL.run_interface(Base.active_repl.t, REPL.LineEdit.ModalInterface([panel, search_prompt]))
  catch e
    Atom.msg("doneWorking")
    Atom.msg("updateWorkspace")
    e isa InterruptException || rethrow(e)
  end
end

# repl completions

struct DebugCompletionProvider <: REPL.CompletionProvider end

function LineEdit.complete_line(c::DebugCompletionProvider, s)
  partial = REPL.beforecursor(s.input_buffer)
  full = LineEdit.input_string(s)

  global STATE
  frame = STATE.frame

  # repl backend completions
  comps, range, should_complete = REPLCompletions.completions(full, lastindex(partial), moduleof(frame))
  ret = map(REPLCompletions.completion_text, comps) |> unique!

  # local completions
  @>> filter!(JuliaInterpreter.locals(frame)) do v
    # ref: https://github.com/JuliaDebug/JuliaInterpreter.jl/blob/master/src/utils.jl#L365-L370
    if v.name == Symbol("#self") && (v.value isa Type || sizeof(v.value) == 0)
      return false
    else
      return startswith(string(v.name), partial)
    end
  end map(v -> string(v.name)) vars -> pushfirst!(ret, vars...)

  return ret, partial[range], should_complete
end
