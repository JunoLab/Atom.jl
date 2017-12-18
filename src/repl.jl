
# FIXME: Should refactor all REPL related functions into a struct that keeps track
#        of global state (terminal size, current prompt, current module etc).
# FIXME: Find a way to reprint what's currently entered in the REPL after changing
#        the module (or delete it in the buffer).

handle("changerepl") do data
  @destruct [prompt || ""] = data
  if !isempty(prompt)
    changeREPLprompt(prompt)
  end
  nothing
end

handle("changemodule") do data
  @destruct [mod || "", cols || 30] = data
  if !isempty(mod)
    parts = split(mod, '.')
    if length(parts) > 1 && parts[1] == "Main"
      shift!(parts)
    end
    if isdebugging()
      changeREPLprompt("debug> ", cols)
    else
      changeREPLprompt("$(join(parts, '.'))> ", cols)
      changeREPLmodule(mod)
    end
  end
  nothing
end

current_prompt = "julia> "

function withREPLprompt(f, prompt, cols = 30)
  old_prompt = current_prompt
  changeREPLprompt("", cols)
  r = f()
  changeREPLprompt(old_prompt, cols)
  return r
end

function changeREPLprompt(prompt, cols = 30)
  islocked(evallock) && return nothing

  global current_prompt = prompt
  isdefined(Base, :active_repl) || return
  repl = Base.active_repl
  main_mode = repl.interface.modes[1]
  main_mode.prompt = "\r"*prompt
  print("\r"*" "^max(cols - 10, 10)*"\r")
  print_with_color(:green, prompt, bold = true)
  nothing
end

function updateworkspace()
  msg("updateWorkspace")
end

function changeREPLmodule(mod)
  islocked(evallock) && return nothing

  mod = getthing(mod)

  isdefined(Base, :active_repl) || return
  repl = Base.active_repl
  main_mode = repl.interface.modes[1]
  main_mode.on_done = Base.REPL.respond(repl, main_mode; pass_empty = false) do line
    if !isempty(line)
      ex = parse(line)
      if isdebugging()
        ret = quote
          Juno.progress(name = "Julia") do p
            try
              lock($evallock)
              Atom.Debugger.interpret($line)
            finally
              Atom.updateworkspace()
              unlock($evallock)
            end
          end
        end
      elseif ex isa Expr && ex.head == :module
        ret = quote
          Juno.progress(name = "Julia") do p
            try
              lock($evallock)
              eval($mod, Expr(:(=), :ans, Expr(:toplevel, parse($line))))
            finally
              Atom.updateworkspace()
              unlock($evallock)
            end
          end
        end
      else
        ret = quote
          Juno.progress(name = "Julia") do p
            try
              lock($evallock)
              eval($mod, Expr(:(=), :ans, parse($line)))
            finally
              Atom.updateworkspace()
              unlock($evallock)
            end
          end
        end
      end
    else
      ret = :(  )
    end
    return ret
  end
end

function initREPL()

end
