using REPL
using REPL.LineEdit
# FIXME: Should refactor all REPL related functions into a struct that keeps track
#        of global state (terminal size, current prompt, current module etc).
# FIXME: Find a way to reprint what's currently entered in the REPL after changing
#        the module (or delete it in the buffer).

using Logging: with_logger
using .Progress: JunoProgressLogger

const REPL_SENTINEL_CHAR = "\u200B"
const REPL_TRIGGER_CHAR = "\e[24~"
const INIT_COMPLETE = Ref(false)

function get_main_mode()
  mode = Base.active_repl.interface.modes[1]
  mode isa LineEdit.Prompt || error("no julia repl mode found")
  mode
end

function isREPL(; before_run_repl = false)
  isdefined(Base, :active_repl) &&
  isdefined(Base.active_repl, :interface) &&
  isdefined(Base.active_repl.interface, :modes) &&
  if before_run_repl
    true
  else
    isdefined(Base.active_repl, :mistate) &&
    isa(Base.active_repl.mistate, REPL.LineEdit.MIState)
  end
end

handle("changeprompt") do prompt
  isREPL() || return

  if !(isempty(prompt))
    changeREPLprompt(prompt)
  end
  nothing
end

handle("changemodule") do data
  isREPL() || return

  @destruct [mod || ""] = data
  if !isempty(mod) && !isdebugging()
    parts = split(mod, '.')
    if length(parts) > 1 && parts[1] == "Main"
      popfirst!(parts)
    end
    changeREPLmodule(mod)
  end
  nothing
end

handle("fullpath") do uri
  return fullREPLpath(uri)
end

handle("validatepath") do uri
  return isfile′(fullREPLpath(uri)[1])
end

const juliaprompt = "julia> "

handle("resetprompt") do linebreak
  isREPL() || return
  linebreak && println()
  changeREPLprompt(juliaprompt)
  nothing
end

const current_prompt = Ref{String}(juliaprompt)

const waiter_in = Channel(0)
const waiter_out = Channel(0)

function instantiate_repl_keybindings(repl)
  mykeys = Dict{Any,Any}(
      REPL_TRIGGER_CHAR => blockinput_frontend
  )
  repl.interface = REPL.setup_interface(repl; extra_repl_keymap = mykeys)
end

function blockinput_frontend(s,o...)
  print(LineEdit.terminal(s), "\r\e[0K\r\e[1A\r")

  return :done
end

function blockinput()
  try
    put!(waiter_out, nothing)
    yield()
    take!(waiter_in)
  catch err
    if err isa InterruptException
      if ASYNC_EVAL_TASK[] !== nothing && !istaskdone(ASYNC_EVAL_TASK[])
        schedule(ASYNC_EVAL_TASK[], err; error = true)
      else
        println(err)
      end
    end
  end
  nothing
end

function hideprompt(f)
  isREPL() || return f()
  isdebugging() && return f()

  repl = Base.active_repl
  mistate = repl.mistate
  mode = mistate.current_mode

  buf = String(take!(copy(LineEdit.buffer(mistate))))

  # clear input buffer
  truncate(LineEdit.buffer(mistate), 0)
  LineEdit.refresh_multi_line(mistate)

  can_write_to_terminal = false

  # clear prompt and restore later
  get_main_mode().prompt = ""

  if INIT_COMPLETE[]
    can_write_to_terminal = something(Atom.@rpc(writeToTerminal("\b$(REPL_SENTINEL_CHAR)$(REPL_TRIGGER_CHAR)")), true)
    can_write_to_terminal && take!(waiter_out)
  end

  r = f()

  flush(stdout)
  flush(stderr)

  sleep(0.05)

  pos = @rpc cursorpos()
  INIT_COMPLETE[] && can_write_to_terminal && put!(waiter_in, nothing)
  pos[1] != 0 && println()

  # restore prompt
  get_main_mode().prompt = current_prompt[]

  if applicable(LineEdit.write_prompt, stdout, mode)
    LineEdit.write_prompt(stdout, mode)
  elseif mode isa LineEdit.PrefixHistoryPrompt || :parent_prompt in fieldnames(typeof(mode))
    LineEdit.write_prompt(stdout, mode.parent_prompt)
  else
    printstyled(stdout, current_prompt[], color=:green)
  end

  truncate(LineEdit.buffer(mistate), 0)

  # restore input buffer
  LineEdit.edit_insert(LineEdit.buffer(mistate), buf)
  LineEdit.refresh_multi_line(mistate)
  r
end

function changeREPLprompt(prompt; color = :green, write = true)
  if strip(prompt) == strip(current_prompt[])
    return nothing
  end

  main_mode = get_main_mode()
  main_mode.prompt = prompt
  main_mode.prompt_prefix = color isa Symbol ?
    sprint() do io
      printstyled(IOContext(io, :color => true), " ", color=color)
    end |> split |> first |> string :
    color
  if Base.active_repl.mistate isa REPL.LineEdit.MIState &&
     Base.active_repl.mistate.current_mode == main_mode &&
     write
    print(stdout, "\e[1K\r")
    REPL.LineEdit.write_prompt(stdout, main_mode)
  end
  current_prompt[] = prompt
  nothing
end

# basically the same as Base's `display_error`, just with different frames removed
function display_error(io, err, st)
  ind = findfirst(frame -> frame.file == Symbol(@__FILE__) && frame.func == :repleval, st)
  st = st[1:(ind == nothing ? end : ind - 2)]
  printstyled(io, "ERROR: "; bold=true, color=Base.error_color())
  showerror(IOContext(io, :limit => true), err, st)
  println(io)
end

function display_parse_error(io, err::Meta.ParseError)
  printstyled(io, "ERROR: "; bold=true, color=Base.error_color())
  printstyled(io, "syntax: ", err.msg; color=Base.error_color())
  println(io)
end

# don't inline this so we can find it in the stacktrace
@noinline repleval(mod, line) = Core.eval(mod, line)

const inREPL = Ref{Bool}(false)

function evalrepl(mod, line)
  if line == REPL_SENTINEL_CHAR && INIT_COMPLETE[]
    return blockinput()
  end

  global ans
  try
    lock(evallock)
    msg("working")
    inREPL[] = true
    fixjunodisplays()
    # this is slow:
    errored = false
    with_logger(JunoProgressLogger()) do
      try
         line = Meta.parse(line)
      catch err
        errored = true
        display_parse_error(stderr, err)
      end
      errored && return nothing
      try
        ans = repleval(mod, line)
      catch err
        # #FIXME: This is a bit weird (there shouldn't be any printing done here), but
        # seems to work just fine.

        errored = true
        display_error(stderr, err, stacktrace(catch_backtrace()))
      end
    end
    errored ? nothing : ans
  catch err
    # This is for internal errors only.
    display_error(stderr, err, stacktrace(catch_backtrace()))
  finally
    inREPL[] = false
    unlock(evallock)
    @async begin
      msg("doneWorking")
      msg("updateWorkspace")
    end
    nothing
  end
end

function changeREPLmodule(mod)
  islocked(evallock) && return nothing

  mod = getmodule(mod)

  # change the repl module in the context of both evaluation and completions
  # NOTE: help_mode doesn't allow custom provider yet:
  # https://github.com/JuliaLang/julia/pull/33102 may help with them all
  main_mode = get_main_mode()
  main_mode.on_done = REPL.respond(Base.active_repl, main_mode; pass_empty = false) do line
    if !isempty(line)
      quote
        $evalrepl($mod, $line)
      end
    end
  end
  main_mode.complete = JunoREPLCompletionProvider(mod)

  INIT_COMPLETE[] = true
end

function reset_repl_history()
  mode = get_main_mode()
  hp = mode.hist
  replc = mode.complete

  if Base.active_repl.history_file
    try
      hist_path = REPL.find_hist_file()
      mkpath(dirname(hist_path))
      f = open(hist_path, read=true, write=true, create=true)
      REPL.hist_from_file(hp, f, hist_path)
      atexit(() -> close(f))
      REPL.history_reset_state(hp)
    catch e
    end
  end
end

# make sure DisplayHook() is higher than REPLDisplay() in the display stack
function fixdisplayorder()
  if isREPL()
    Media.unsetdisplay(Editor(), Any)
    fixjunodisplays()
  end
end

function fixjunodisplays()
  for d in reverse(Base.Multimedia.displays)
    if d isa JunoDisplay
      popdisplay(JunoDisplay())
    end
  end
  pushdisplay(JunoDisplay())
end

# completions

struct JunoREPLCompletionProvider <: REPL.CompletionProvider
  mod::Module
end

function LineEdit.complete_line(c::JunoREPLCompletionProvider, s)
  partial = REPL.beforecursor(s.input_buffer)
  full = LineEdit.input_string(s)

  # module-aware repl backend completions
  comps, range, should_complete = REPLCompletions.completions(full, lastindex(partial), c.mod)
  ret = map(REPLCompletions.completion_text, comps) |> unique!

  return ret, partial[range], should_complete
end
