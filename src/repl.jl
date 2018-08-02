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
  if applicable(REPL.LineEdit.write_prompt, stdout, mistate.current_mode)
    REPL.LineEdit.write_prompt(stdout, mistate.current_mode)
  else # for history prompts
    changeREPLprompt(current_prompt)
  end
  # Restore input buffer:
  print(String(take!(copy(LineEdit.buffer(mistate)))))
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

function changeREPLmodule(mod)
  islocked(evallock) && return nothing

  mod = getthing(mod)

  main_mode = get_main_mode()
  main_mode.on_done = REPL.respond(Base.active_repl, main_mode; pass_empty = false) do line
    if !isempty(line)
      quote
        try
          lock($evallock)
          $msg("working")
          # this is slow:
          Base.CoreLogging.with_logger($(Atom.JunoProgressLogger)(Base.CoreLogging.current_logger())) do
            global ans = Core.eval($mod, Meta.parse($line))
          end
          ans
        finally
          unlock($evallock)
          $msg("doneWorking")
          @async $msg("updateWorkspace")
        end
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
    Base.Multimedia.pushdisplay(JunoDisplay())
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
