using CodeTools, LNR, Media
import REPL

using Logging: with_logger
using .Progress: JunoProgressLogger

ends_with_semicolon(x) = REPL.ends_with_semicolon(split(x,'\n',keepempty = false)[end])

LNR.cursor(data::AbstractDict) = cursor(data["row"], data["column"])

exit_on_sigint(on) = ccall(:jl_exit_on_sigint, Nothing, (Cint,), on)

function modulenames(data, pos)
  main = haskey(data, "module") ? data["module"] :
         haskey(data, "path") ? CodeTools.filemodule(data["path"]) :
         "Main"
  main == "" && (main = "Main")
  sub = CodeTools.codemodule(data["code"], pos)
  main, sub
end

handle("module") do data
  main, sub = modulenames(data, cursor(data))

  mod = CodeTools.getmodule(main)
  smod = CodeTools.getmodule(mod, sub)

  return d(:main => main,
           :sub  => sub,
           :inactive => (mod==nothing),
           :subInactive => smod==nothing)
end

handle("allmodules") do
  sort!([string(m) for m in CodeTools.allchildren(Main)])
end

isselection(data) = data["start"] ≠ data["stop"]

withpath(f, path) =
  CodeTools.withpath(f, path == nothing || isuntitled(path) ? nothing : path)

const evallock = ReentrantLock()

handle("evalshow") do data
  fixjunodisplays()
  @dynamic let Media.input = Editor()
    @destruct [text, line, path, mod] = data
    mod = getmodule(mod)

    lock(evallock)
    result = hideprompt() do
      with_logger(JunoProgressLogger()) do
        withpath(path) do
          try
            res = include_string(mod, text, path, line)
            res ≠ nothing && !ends_with_semicolon(text) && display(res)
            res
          catch e
            # should hide parts of the backtrace here
            Base.display_error(stderr, e, catch_backtrace())
          end
        end
      end
    end
    unlock(evallock)

    Base.invokelatest() do
      display = Media.getdisplay(typeof(result), Media.pool(Editor()), default = Editor())
      !isa(result, EvalError) && ends_with_semicolon(text) && (result = nothing)
      display ≠ Editor() && result ≠ nothing && @ierrs render(display, result)
    end

    nothing
  end
end

handle("eval") do data
  fixjunodisplays()
  @dynamic let Media.input = Editor()
    @destruct [text, line, path, mod, displaymode || "editor"] = data
    mod = getmodule(mod)

    lock(evallock)
    result = hideprompt() do
      with_logger(JunoProgressLogger()) do
        withpath(path) do
          @errs include_string(mod, text, path, line)
        end
      end
    end
    unlock(evallock)

    Base.invokelatest() do
      !isa(result, EvalError) && ends_with_semicolon(text) && (result = nothing)
      @ierrs displayandrender(result)
    end
  end
end

handle("evalall") do data
  fixjunodisplays()
  @dynamic let Media.input = Editor()
    @destruct [setmod = :module || nothing, path || "untitled", code] = data
    mod = if setmod ≠ nothing
       getmodule(setmod)
    elseif isabspath(path)
      getmodule(CodeTools.filemodule(path))
    else
      Main
    end

    lock(evallock)
    hideprompt() do
      with_logger(JunoProgressLogger()) do
        withpath(path) do
          result = nothing
          try
            result = include_string(mod, code, path)
          catch e
            bt = catch_backtrace()
            st = cliptrace(stacktrace(bt))
            ee = EvalError(e, st)
            if isREPL()
              printstyled(stderr, "ERROR: "; bold=true, color=Base.error_color())
              Base.showerror(IOContext(stderr, :limit => true), e, st)
              println(stderr)
            else
              render(Console(), ee)
            end
            @msg error(d(:msg => "Error evaluating $(basename(path))",
                         :detail => string(ee),
                         :dismissable => true))
          end
          Base.invokelatest() do
            @ierrs displayandrender(result)
          end
        end
      end
    end
    unlock(evallock)
  end
  return
end

handle("docs") do data
  @destruct [mod || "Main", word] = data
  docstring = @errs getdocs(mod, word)

  docstring isa EvalError && return Dict(:error => true)

  mtable = try getmethods(mod, word)
    catch e
      []
    end

  Dict(:error    => false,
       :type     => :dom,
       :tag      => :div,
       :contents =>  map(x -> render(Inline(), x), [docstring; mtable]))
end

handle("methods") do data
  @destruct [mod || "Main", word] = data
  mtable = @errs getmethods(mod, word)
  if mtable isa EvalError
    Dict(:error => true, :items => sprint(showerror, mtable.err))
  else
    # only show the method with full default arguments
    aggregated = @>> mtable collect sort(by = m -> m.nargs, rev = true) unique(m -> (m.file, m.line))
    Dict(:error => false, :items => [gotoitem(m) for m in aggregated])
  end
end

function gotoitem(m::Method)
  _, link = view(m)
  sig = sprint(show, m)
  sig = replace(sig, r" in .* at .*$" => "")
  Dict(:text => sig,
       :file => link.file,
       :line => link.line - 1,
       :secondary => join(link.contents))
end
