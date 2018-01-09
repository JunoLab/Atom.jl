
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
  if !isempty(mod)
    parts = split(mod, '.')
    if length(parts) > 1 && parts[1] == "Main"
      shift!(parts)
    end
    if isdebugging()
      changeREPLprompt("debug> ")
    else
      changeREPLmodule(mod)
    end
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

  didWrite = false

  outreader = @async begin
    didWriteLinebreak = false
    while isopen(rout)
      if isopen(rout)
        r = readavailable(rout)
        didRead = length(r) > 0
        if !didWrite && didRead
          print(origout, "\r         \r")
        end
        didWrite |= didRead
        write(origout, r)
      end

      if didRead
        didWriteLinebreak = r[end] == 0x0a
      end
    end
    didWriteLinebreak
  end

  errreader = @async begin
    didWriteLinebreak = false
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
    didWriteLinebreak
  end

  local res
  didWriteLinebreakOut, didWriteLinebreakErr = false, false

  try
    res = f()
  finally
    redirect_stdout(origout)
    redirect_stderr(origerr)
    close(wout)
    close(werr)
    didWriteLinebreakOut = wait(outreader)
    didWriteLinebreakErr = wait(errreader)
  end

  res, didWrite, didWriteLinebreakOut || didWriteLinebreakErr
end


function changeREPLprompt(prompt)
  global current_prompt = prompt
  repl = Base.active_repl
  main_mode = repl.interface.modes[1]
  main_mode.prompt = prompt
  print("\r       \r")
  print_with_color(:green, prompt, bold = true)
  true
end

function updateworkspace()
  msg("updateWorkspace")
end

# FIXME: this breaks horribly when `Juno.@enter` is called in the REPL.
function changeREPLmodule(mod)
  islocked(evallock) && return nothing

  mod = getthing(mod)

  repl = Base.active_repl
  main_mode = repl.interface.modes[1]
  main_mode.on_done = Base.REPL.respond(repl, main_mode; pass_empty = false) do line
    if !isempty(line)
      ex = parse(line)
      if isdebugging()
        ret = quote
          Atom.Progress.progress(name = "Debugging") do p
            try
              lock($evallock)
              Atom.Debugger.interpret($line)
            finally
              Atom.updateworkspace()
              unlock($evallock)
            end
          end
        end
      else
        ret = quote
          Atom.Progress.progress(name = "Julia") do p
            try
              lock($evallock)
              eval($mod, :(ans = eval(parse($$line))))
            finally
              Atom.updateworkspace()
              unlock($evallock)
            end
          end
        end
      end
    end
    return ret
  end
end

struct PlotPaneDisplay <: Base.Multimedia.Display end

function Base.display(d::PlotPaneDisplay, m::Union{MIME"image/png",
                                                   MIME"image/svg+xml",
                                                   MIME"juno/plotpane"}, plt)
  Juno.render(Juno.PlotPane(), HTML(stringmime(MIME("text/html"), plt)))
end

function Base.display(d::PlotPaneDisplay, x)
  if mimewritable("image/svg+xml", x)
    display(d, "image/svg+xml", x)
  elseif mimewritable("image/png", x)
    display(d, "image/png", x)
  elseif mimewriteable("juno/plotpane", x)
    display(d, "juno/plotpane", x)
  else
    throw(MethodError(display, (d, x)))
  end
end

displayble(d::PlotPaneDisplay, ::MIME"image/png") = true
displayble(d::PlotPaneDisplay, ::MIME"image/svg+xml") = true

@init begin
  atreplinit((i) -> pushdisplay(PlotPaneDisplay()))
end
