using CodeTools, LNR, Media
import CodeTools: getthing
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

function getmodule(data, pos)
  main, sub = modulenames(data, pos)
  getthing("$main.$sub", getthing(main, Main))
end

getmodule(mod::String) = get(Base.loaded_modules, first(filter(x->x.name==mod, collect(keys(Base.loaded_modules)))), Main)

handle("module") do data
  main, sub = modulenames(data, cursor(data))

  inactive_k = filter(x -> x.name == main, keys(Base.loaded_modules))

  return d(:main => main,
           :sub  => sub,
           :inactive => isempty(inactive_k),
           :subInactive => (getthing("$main.$sub") == nothing))
end

handle("allmodules") do
  sort!([string(m) for m in CodeTools.allchildren(Main)])
end

isselection(data) = data["start"] ≠ data["stop"]

withpath(f, path) =
  CodeTools.withpath(f, path == nothing || isuntitled(path) ? nothing : path)

const evallock = ReentrantLock()

handle("evalshow") do data
  @dynamic let Media.input = Editor()
    @destruct [text, line, path, mod] = data
    mod = getmodule(mod)

    lock(evallock)
    result = hideprompt() do
      withpath(path) do
        with_logger(JunoProgressLogger(current_logger())) do
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
  @dynamic let Media.input = Editor()
    @destruct [text, line, path, mod, displaymode || "editor"] = data
    mod = getmodule(mod)

    lock(evallock)
    result = hideprompt() do
      withpath(path) do
        with_logger(JunoProgressLogger(current_logger())) do
          @errs include_string(mod, text, path, line)
        end
      end
    end
    unlock(evallock)

    Base.invokelatest() do
      display = Media.getdisplay(typeof(result), Media.pool(Editor()), default = Editor())
      !isa(result, EvalError) && ends_with_semicolon(text) && (result = nothing)
      display ≠ Editor() && result ≠ nothing && render(display, result)
      render′(Editor(), result)
    end
  end
end

handle("evalall") do data
  @dynamic let Media.input = Editor()
    @destruct [setmod = :module || nothing, path || "untitled", code] = data
    if setmod ≠ nothing
      mod = getmodule(setmod)
    elseif isabspath(path)
      mod = getmodule(CodeTools.filemodule(path))
    end

    lock(evallock)
    hideprompt() do
      withpath(path) do
        with_logger(JunoProgressLogger(current_logger())) do
          try
            include_string(mod, code, path)
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
        end
      end
    end
    unlock(evallock)
  end
  return
end


handle("evalrepl") do data
  @dynamic let Media.input = Console()
    @destruct [mode || nothing, code, mod || "Main"] = data
    if mode == "shell"
      code = "Base.repl_cmd(`$code`, STDOUT)"
    elseif mode == "help"
      render′(@errs getdocs(mod, code))
      return
    end
    mod = getmodule(mod)
    if isdebugging()
      render(Console(), @errs Debugger.interpret(code))
    else
      try
        lock(evallock)
        withpath(nothing) do
          with_logger(JunoProgressLogger(current_logger())) do
            result = @errs eval(mod, :(ans = include_string($mod, $code, "console")))
            !isa(result,EvalError) && ends_with_semicolon(code) && (result = nothing)
            Base.invokelatest(render′, result)
          end
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
  mod = getmodule(mod)
  Core.eval(mod, :(Base.methods($(Symbol(word)))))
end

function getdocs(mod, word)
  if Symbol(word) in keys(Docs.keywords)
    Core.eval(:(@doc($(Symbol(word)))))
  else
    include_string(getmodule(mod), "@doc $word")
  end
end

function gotoitem(m::Method)
  _, link = view(m)
  sig = sprint(show, m)
  sig = sig[1:something(findlast(isequal(')'), sig), 0)]
  Dict(:text => sig,
       :file => link.file,
       :line => link.line - 1,
       :secondary => join(link.contents))
end

ismacro(f::Function) = startswith(string(methods(f).mt.name), "@")

wstype(x) = ""
wstype(::Module) = "module"
wstype(f::Function) = ismacro(f) ? "mixin" : "function"
wstype(::Type) = "type"
wstype(::Expr) = "mixin"
wstype(::Symbol) = "tag"
wstype(::AbstractString) = "property"
wstype(::Number) = "constant"
wstype(::Exception) = "tag"

wsicon(x) = ""
wsicon(f::Function) = ismacro(f) ? "icon-mention" : ""
wsicon(::AbstractArray) = "icon-file-binary"
wsicon(::AbstractVector) = "icon-list-ordered"
wsicon(::AbstractString) = "icon-quote"
wsicon(::Expr) = "icon-code"
wsicon(::Symbol) = "icon-code"
wsicon(::Exception) = "icon-bug"
wsicon(::Number) = "n"

wsnamed(name, val) = false
wsnamed(name, f::Function) = name == methods(f).mt.name
wsnamed(name, m::Module) = name == module_name(m)
wsnamed(name, T::DataType) = name == Symbol(T.name)

function wsitem(name, val)
  d(:name  => name,
    :value => render′(Inline(), val),
    :type  => wstype(val),
    :icon  => wsicon(val))
end

wsitem(mod::Module, name::Symbol) = wsitem(name, getfield(mod, name))

handle("workspace") do mod
  mod = getmodule(mod)
  ns = filter!(x->!Base.isdeprecated(mod, x), Symbol.(CodeTools.filtervalid(names(mod, true))))
  filter!(n -> isdefined(mod, n), ns)
  # TODO: only filter out imported modules
  filter!(n -> !isa(getfield(mod, n), Module), ns)
  contexts = [d(:context => string(mod), :items => map(n -> wsitem(mod, n), ns))]
  if isdebugging()
    prepend!(contexts, Debugger.contexts())
  end
  return contexts
end
