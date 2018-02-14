
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

CURRENT_EVAL_TASK = nothing
LAST_WRITTEN_BYTE = 0x00
NEW_STDOUT_R, NEW_STDERR_R = nothing, nothing

function initREPLlistener()
  global ORIGSTDOUT = STDOUT
  global ORIGSTDERR = STDERR

  global NEW_STDOUT_R
  global NEW_STDERR_R

  NEW_STDOUT_R, wout = redirect_stdout()
  NEW_STDERR_R, werr = redirect_stderr()

  listen_in = (instream, outstream) -> begin
    while true
      try
        while isopen(instream)
          try
            yield()
            data = readavailable(instream)
            if length(data) > 0
              global LAST_WRITTEN_BYTE
              LAST_WRITTEN_BYTE == 0x00 && print(outstream, "\e[1K\r")
              LAST_WRITTEN_BYTE = data[end]
            end
            write(outstream, data)
            yield()
          catch e
            schedule(CURRENT_EVAL_TASK, InterruptException(); error=true)
          end
        end
      end
    end
  end

  global ERR_READER = @async listen_in(NEW_STDERR_R, ORIGSTDERR)
  global OUT_READER = @async listen_in(NEW_STDOUT_R, ORIGSTDOUT)
end

function didWriteToREPL(f)
  global CURRENT_EVAL_TASK
  global LAST_WRITTEN_BYTE

  CURRENT_EVAL_TASK = current_task()
  LAST_WRITTEN_BYTE = 0x00

  res = f()

  yield()
  flush(NEW_STDERR_R)
  flush(NEW_STDOUT_R)
  yield()
  flush(STDOUT)
  flush(STDERR)
  # FIXME: should be unnessecary, but flush() and yield() aren't always enough;
  # downside of inherently racy code I suppose :)
  sleep(0.01)

  res, LAST_WRITTEN_BYTE != 0x00, LAST_WRITTEN_BYTE == 0x0a
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
    initREPLlistener()
  end)
end
