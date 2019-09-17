using REPL
using REPL.LineEdit
using REPL.REPLCompletions
using JuliaInterpreter: locals

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

# completions

struct JunoDebuggerRPELCompletionProvider <: REPL.CompletionProvider end

function LineEdit.complete_line(c::JunoDebuggerRPELCompletionProvider, s)
  partial = REPL.beforecursor(s.input_buffer)
  full = LineEdit.input_string(s)

  frame = STATE.frame

  # module-aware repl backend completions
  comps, range, should_complete = REPLCompletions.completions(full, lastindex(partial), moduleof(frame))
  ret = map(REPLCompletions.completion_text, comps) |> unique!

  # make local completions appear first: verbose ?
  vars = @>> locals(frame) map(v -> string(v.name))
  inds = []
  comps = []
  for (i, c) ∈ enumerate(ret)
    if c ∈ vars
      push!(inds, i)
      push!(comps, c)
    end
  end
  deleteat!(ret, inds)
  pushfirst!(ret, comps...)

  return ret, partial[range], should_complete
end
