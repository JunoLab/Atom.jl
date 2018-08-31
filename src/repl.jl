using REPL
using REPL: LineEdit
# FIXME: Should refactor all REPL related functions into a struct that keeps track
#        of global state (terminal size, current prompt, current module etc).
# FIXME: Find a way to reprint what's currently entered in the REPL after changing
#        the module (or delete it in the buffer).

function get_main_mode()
  mode = Base.active_repl.interface.modes[1]
  mode isa LineEdit.Prompt || error("no julia repl mode found")
  mode
end

isREPL() = isdefined(Base, :active_repl)

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

function fullREPLpath(uri)
  uri1 = match(r"(.+?)(?:\:(\d+))?$", uri)
  uri2 = match(r"@ ([^\s]+)\s(.*?)\:(\d+)", uri)
  if uri2 !== nothing
    return normpath(expanduser(String(uri2[2]))), parse(Int, uri2[3])
  elseif uri1 !== nothing
    line = uri1[2] ≠ nothing ? parse(Int, uri1[2]) : 0
    return Atom.fullpath(uri1[1]), line
  end
  return "", 0
end

handle("fullpath") do uri
  return fullREPLpath(uri)
end

handle("validatepath") do uri
  return isfile(fullREPLpath(uri)[1])
end

juliaprompt = "julia> "

handle("resetprompt") do linebreak
  isREPL() || return
  linebreak && println()
  changeREPLprompt(juliaprompt)
  nothing
end

current_prompt = juliaprompt

function hideprompt(f)
  isREPL() || return f()

  print(stdout, "\e[1K\r")
  flush(stdout)
  flush(stderr)
  r = f()
  flush(stdout)
  flush(stderr)
  sleep(0.05)

  pos = @rpc cursorpos()
  pos[1] != 0 && println()

  # restore prompt
  mistate = Base.active_repl.mistate
  mode = mistate.current_mode
  if applicable(REPL.LineEdit.write_prompt, stdout, mode)
    REPL.LineEdit.write_prompt(stdout, mode)
  elseif mode isa REPL.LineEdit.PrefixHistoryPrompt || :parent_prompt in fieldnames(typeof(mode))
    REPL.LineEdit.write_prompt(stdout, mode.parent_prompt)
  else
    printstyled(stdout, current_prompt, color=:green)
  end
  # Restore input buffer:
  print(stdout, String(take!(copy(LineEdit.buffer(mistate)))))
  r
end

function changeREPLprompt(prompt; color = :green)
  if strip(prompt) == strip(current_prompt)
    return nothing
  end

  main_mode = get_main_mode()
  main_mode.prompt = prompt
  if Base.active_repl.mistate.current_mode == main_mode
    print(stdout, "\e[1K\r")
    REPL.LineEdit.write_prompt(stdout, main_mode)
  end
  global current_prompt = prompt
  nothing
end

# basically the same as Base's `display_error`, just with different frames removed
function display_error(io, err, st)
  ind = findfirst(frame -> frame.file == Symbol(@__FILE__), st)
  st = st[1:(ind == nothing ? end : ind - 2)]
  printstyled(io, "ERROR: "; bold=true, color=Base.error_color())
  showerror(IOContext(io, :limit => true), err, st)
  println(io)
end

function evalrepl(mod, line)
  try
    lock(evallock)
    msg("working")
    fixjunodisplays()
    # this is slow:
    Base.CoreLogging.with_logger(Atom.JunoProgressLogger(Base.CoreLogging.current_logger())) do
      global ans = Core.eval(mod, Meta.parse(line))
    end
    ans
  catch err
    # #FIXME: This is a bit weird (there shouldn't be any printing done here), but
    # seems to work just fine.
    display_error(stderr, err, stacktrace(catch_backtrace()))
  finally
    unlock(evallock)
    msg("doneWorking")
    @async msg("updateWorkspace")
  end
end

function changeREPLmodule(mod)
  islocked(evallock) && return nothing

  mod = getthing(mod)

  main_mode = get_main_mode()
  main_mode.on_done = REPL.respond(Base.active_repl, main_mode; pass_empty = false) do line
    if !isempty(line)
      quote
        $evalrepl($mod, $line)
      end
    end
  end
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
          finalizer(replc) do replc
              close(f)
          end
          REPL.hist_from_file(hp, f, hist_path)
          REPL.history_reset_state(hp)
      catch e
      end
  end
end

# make sure DisplayHook() is higher than REPLDisplay() in the display stack
function fixdisplayorder()
  if isREPL()
    Media.unsetdisplay(Editor(), Any)
    Base.Multimedia.popdisplay(Media.DisplayHook())
    Base.Multimedia.pushdisplay(Media.DisplayHook())
    fixjunodisplays()
  end
end

function fixjunodisplays()
  if isREPL()
    for d in reverse(Base.Multimedia.displays)
      if d isa JunoDisplay
        popdisplay(JunoDisplay())
      end
    end
    pushdisplay(JunoDisplay())
  end
end

@init begin
  atreplinit(i -> fixdisplayorder())

  Atom.handle("connected") do
    reset_repl_history()
    fixdisplayorder()
    nothing
  end
end
