
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

handle("resetprompt") do
  isREPL() || return
  changeREPLprompt("julia> ")
  nothing
end

current_prompt = "julia> "

function hideprompt(f)
  isREPL() || return f()

  local r
  didWrite = false
  didWriteLinebreak = false
  try
    r, didWrite, didWriteLinebreak = didWriteToREPL(f)
  finally
    didWrite && !didWriteLinebreak && println()
    didWrite && changeREPLprompt("julia> ")
  end
  r
end

function didWriteToREPL(f)
  origout, origerr = STDOUT, STDERR

  rout, wout = redirect_stdout()
  rerr, werr = redirect_stderr()

  ct = current_task()

  didWrite = false

  outreader = @async begin
    didWriteLinebreak = false
    try
      while isopen(rout)
        r = readavailable(rout)
        didRead = length(r) > 0
        if !didWrite && didRead
          print(origout, "\r         \r")
        end
        didWrite |= didRead
        write(origout, r)

        if didRead
          didWriteLinebreak = r[end] == 0x0a
        end
      end
    catch e
      Base.throwto(ct, e)
    end
    didWriteLinebreak
  end

  errreader = @async begin
    didWriteLinebreak = false
    try
      while isopen(rerr)
        r = readavailable(rerr)
        didRead = length(r) > 0
        if !didWrite && didRead
          print(origout, "\r         \r")
        end
        didWrite |= didRead
        write(origerr, r)

        if didRead
          didWriteLinebreak = r[end] == 0x0a
        end
      end
    catch e
      Base.throwto(ct, e)
    end
    didWriteLinebreak
  end

  didWriteLinebreakOut, didWriteLinebreakErr = false, false

  res = f()
  redirect_stdout(origout)
  redirect_stderr(origerr)

  close(wout); close(rout)
  close(werr); close(rerr)

  if !(res isa EvalError)
    didWriteLinebreakOut = wait(outreader)
    didWriteLinebreakErr = wait(errreader)
  end

  res, didWrite, didWriteLinebreakOut || didWriteLinebreakErr
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
  end)
end
