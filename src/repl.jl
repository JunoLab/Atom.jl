
# FIXME: Should refactor all REPL related functions into a struct that keeps track
#        of global state (terminal size, current prompt, current module etc).
# FIXME: Find a way to reprint what's currently entered in the REPL after changing
#        the module (or delete it in the buffer).

isREPL() = isdefined(Base, :active_repl)

handle("changerepl") do data
  isREPL() || return

  @destruct [prompt || ""] = data
  if !isempty(prompt)
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
      shift!(parts)
    end
    changeREPLmodule(mod)
  end
  nothing
end

handle("fullpath") do uri
  return Atom.fullpath(uri)
end

handle("validatepath") do uri
  uri = match(r"(.+)(:\d+)$", uri)
  if uri == nothing
    return false
  end
  uri = Atom.fullpath(uri[1])
  if isfile(uri) || isdir(uri)
    return true
  else
    return false
  end
end

handle("resetprompt") do linebreak
  isREPL() || return
  linebreak && println()
  changeREPLprompt("julia> ")
  nothing
end

current_prompt = "julia> "

function hideprompt(f)
  isREPL() || return f()

  print("\e[1K\r")
  flush(STDOUT)
  flush(STDERR)
  r = f()
  flush(STDOUT)
  flush(STDERR)
  sleep(0.03)

  pos = @rpc cursorpos()
  pos[1] != 0 && println()
  changeREPLprompt("julia> ")
  r
end

function changeREPLprompt(prompt; color = :green)
  global current_prompt = prompt
  repl = Base.active_repl
  main_mode = repl.interface.modes[1]
  main_mode.prompt = prompt
  main_mode.prompt_prefix = Base.text_colors[:bold] * Base.text_colors[color]
  print("\r       \r")
  print_with_color(color, prompt, bold = true)
  true
end

# FIXME: This is ugly and bad, but lets us work around the fact that REPL.run_interface
#        doesn't seem to stop the currently active repl from running. This global
#        switches between two interpreter codepaths when debugging over in ./debugger/stepper.jl.
repleval = false

function changeREPLmodule(mod)
  islocked(evallock) && return nothing

  mod = getthing(mod)

  repl = Base.active_repl
  main_mode = repl.interface.modes[1]
  main_mode.on_done = Base.REPL.respond(repl, main_mode; pass_empty = false) do line
    if !isempty(line)
      if isdebugging()
        quote
          try
            Atom.msg("working")
            Atom.Debugger.interpret($line)
          finally
            Atom.msg("updateWorkspace")
            Atom.msg("doneWorking")
          end
        end
      else
        quote
          try
            lock($evallock)
            Atom.msg("working")
            eval(Atom, :(repleval = true))
            eval($mod, :(ans = eval(parse($$line))))
          finally
            Atom.msg("updateWorkspace")
            unlock($evallock)
            Atom.msg("doneWorking")
            eval(Atom, :(repleval = false))
          end
        end
      end
    end
  end
end

# make sure DisplayHook() is higher than REPLDisplay() in the display stack
@init begin
  atreplinit((i) -> begin
    Base.Multimedia.popdisplay(Media.DisplayHook())
    Base.Multimedia.pushdisplay(Media.DisplayHook())
    Media.unsetdisplay(Editor(), Any)
  end)
end
