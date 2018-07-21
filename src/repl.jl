using REPL
using REPL: LineEdit
# FIXME: Should refactor all REPL related functions into a struct that keeps track
#        of global state (terminal size, current prompt, current module etc).
# FIXME: Find a way to reprint what's currently entered in the REPL after changing
#        the module (or delete it in the buffer).

function get_main_mode()
  for mode in Base.active_repl.interface.modes
    if mode isa LineEdit.Prompt
      if mode.prompt == current_prompt
        return mode
      end
    end
  end
  error("no julia repl mode found")
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

handle("fullpath") do uri
  uri1 = match(r"(.+)\:(\d+)$", uri)
  uri2 = match(r"@ ([^\s]+)\s(.*?)\:(\d+)", uri)
  if uri2 !== nothing
    return Atom.package_file_path(String(uri2[1]), String(uri2[2])), parse(Int, uri2[3])
  elseif uri1 !== nothing
    return Atom.fullpath(uri1[1]), parse(Int, uri1[2])
  end
  return "", 0
end

function package_file_path(pkg, sfile)
  occursin(".", pkg) && (pkg = String(first(split(pkg, '.'))))

  pkg == "Main" && return nothing

  path = if pkg in ("Base", "Core")
    Atom.basepath("")
  else
    Base.locate_package(Base.identify_package(pkg))
  end

  path == nothing && return nothing

  for (root, _, files) in walkdir(dirname(path))
    for file in files
      basename(file) == sfile && (return joinpath(root, file))
    end
  end
  return nothing
end

handle("validatepath") do uri
  uri1 = match(r"(.+?)(:\d+)?$", uri)
  uri2 = match(r"@ ([^\s]+)\s(.*?)\:(\d+)", uri)
  if uri2 ≠ nothing
    # FIXME: always returns the first found file
    path = package_file_path(String(uri2[1]), String(uri2[2]))
    return path ≠ nothing
  elseif uri1 ≠ nothing
    path = Atom.fullpath(uri1[1])
    return isfile(path)
  else
    return false
  end
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

# make sure DisplayHook() is higher than REPLDisplay() in the display stack
@init begin
  atreplinit((i) -> begin
    Media.unsetdisplay(Editor(), Any)
    Base.Multimedia.popdisplay(Media.DisplayHook())
    Base.Multimedia.pushdisplay(Media.DisplayHook())
    Base.Multimedia.pushdisplay(JunoDisplay())
  end)
end
