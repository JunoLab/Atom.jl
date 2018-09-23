using CodeTools, LNR, Media
using CodeTools: getthing, getmodule
import REPL

using Logging: with_logger, current_logger
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

function getmodule′(args...)
  m = getmodule(args...)
  return m == nothing ? Main : m
end

handle("module") do data
  main, sub = modulenames(data, cursor(data))

  mod = getmodule(main)
  smod = getmodule(mod, sub)

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
    mod = getmodule′(mod)

    lock(evallock)
    result = hideprompt() do
      withpath(path) do
        try
          res = include_string(mod, text, path, line)
          res ≠ nothing && display(res)
          res
        catch e
          # should hide parts of the backtrace here
          Base.display_error(stderr, e, catch_backtrace())
        end
      end
    end
    unlock(evallock)

    Base.invokelatest() do
      display = Media.getdisplay(typeof(result), Media.pool(Editor()), default = Editor())
      !isa(result, EvalError) && ends_with_semicolon(text) && (result = nothing)
      display ≠ Editor() && result ≠ nothing && render(display, result)
    end

    nothing
  end
end

handle("eval") do data
  fixjunodisplays()
  @dynamic let Media.input = Editor()
    @destruct [text, line, path, mod, displaymode || "editor"] = data
    mod = getmodule′(mod)

    lock(evallock)
    result = hideprompt() do
      withpath(path) do
        @errs include_string(mod, text, path, line)
      end
    end
    unlock(evallock)

    Base.invokelatest() do
      !isa(result, EvalError) && ends_with_semicolon(text) && (result = nothing)
      displayandrender(result)
    end
  end
end

handle("evalall") do data
  fixjunodisplays()
  @dynamic let Media.input = Editor()
    @destruct [setmod = :module || nothing, path || "untitled", code] = data
    mod = if setmod ≠ nothing
       getmodule′(setmod)
    elseif isabspath(path)
      getmodule′(CodeTools.filemodule(path))
    else
      Main
    end

    lock(evallock)
    hideprompt() do
      withpath(path) do
        result = nothing
        try
          result = include_string(mod, code, path)
        catch e
          bt = catch_backtrace()
          ee = EvalError(e, stacktrace(bt))
          if isREPL()
            printstyled(stderr, "ERROR: ", color=:red)
            Base.showerror(stderr, e, bt)
            println(stderr)
          else
            render(Console(), ee)
          end
          @msg error(d(:msg => "Error evaluating $(basename(path))",
                       :detail => string(ee),
                       :dismissable => true))
        end
        Base.invokelatest() do
          displayandrender(result)
        end
      end
    end
    unlock(evallock)
  end
  return
end


handle("evalrepl") do data
  fixjunodisplays()
  @dynamic let Media.input = Console()
    @destruct [mode || nothing, code, mod || "Main"] = data
    if mode == "shell"
      code = "Base.repl_cmd(`$code`, STDOUT)"
    elseif mode == "help"
      render′(@errs getdocs(mod, code))
      return
    end
    mod = getmodule′(mod)
    if isdebugging()
      render(Console(), @errs Debugger.interpret(code))
    else
      try
        lock(evallock)
        withpath(nothing) do
          result = @errs Core.eval(mod, :(ans = include_string($mod, $code, "console")))
          !isa(result,EvalError) && ends_with_semicolon(code) && (result = nothing)
          Base.invokelatest(render′, result)
        end
        unlock(evallock)
      catch e
        showerror(stderr, e, catch_stacktrace())
      end
    end
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
    Dict(:items => [gotoitem(m) for m in mtable])
  end
end

function getmethods(mod, word)
  methods(CodeTools.getthing(getmodule′(mod), word))
end

function getdocs(mod, word)
  md = if Symbol(word) in keys(Docs.keywords)
    Core.eval(Main, :(@doc($(Symbol(word)))))
  else
    include_string(getmodule′(mod), "@doc $word")
  end
  return md_hlines(md)
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
