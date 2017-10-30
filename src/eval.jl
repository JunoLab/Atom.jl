using CodeTools, LNR, Media
import CodeTools: getthing

ends_with_semicolon(x) = Base.REPL.ends_with_semicolon(split(x,'\n',keep = false)[end])

LNR.cursor(data::Associative) = cursor(data["row"], data["column"])

exit_on_sigint(on) = ccall(:jl_exit_on_sigint, Void, (Cint,), on)

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

handle("module") do data
  main, sub = modulenames(data, cursor(data))
  return d(:main => main,
           :sub  => sub,
           :inactive => (getthing(main) == nothing),
           :subInactive => (getthing("$main.$sub") == nothing))
end

handle("allmodules") do
  sort!([string(m) for m in CodeTools.allchildren(Main)])
end

isselection(data) = data["start"] ≠ data["stop"]

withpath(f, path) =
  CodeTools.withpath(f, path == nothing || isuntitled(path) ? nothing : path)

const evallock = ReentrantLock()

handle("eval") do data
  @dynamic let Media.input = Editor()
    @destruct [text, line, path, mod] = data
    mod = getthing(mod)

    lock(evallock)
    result = withpath(path) do
      @errs include_string(mod, text, path, line)
    end
    unlock(evallock)
    Base.invokelatest() do
      display = Media.getdisplay(typeof(result), Media.pool(Editor()), default = Editor())
      !isa(result,EvalError) && ends_with_semicolon(text) && (result = nothing)
      display ≠ Editor() && result ≠ nothing && render(display, result)
      render′(Editor(), result)
    end
  end
end

handle("evalall") do data
  @dynamic let Media.input = Editor()
    @destruct [setmod = :module || nothing, path || "untitled", code] = data
    mod = Main
    if setmod ≠ nothing
      mod = getthing(setmod, Main)
    elseif isabspath(path)
      mod = getthing(CodeTools.filemodule(path), Main)
    end
    lock(evallock)
    withpath(path) do
      try
        include_string(mod, code, path)
      catch e
        ee = EvalError(e, catch_stacktrace())
        render(Console(), ee)
        @msg error(d(:msg => "Error evaluating $(basename(path))",
                     :detail => string(ee),
                     :dismissable => true))
      end
    end
    unlock(evallock)
  end
  return
end

handle("evalrepl") do data
  @dynamic let Media.input = Console()
    @destruct [mode || nothing, code, mod || "Main"] = data
    mod = getthing(mod)
    if mode == "shell"
      code = "Base.repl_cmd(`$code`, STDOUT)"
    elseif mode == "help"
      render′(@errs getdocs(mod, code))
      return
    end
    if isdebugging()
      render(Console(), @errs Debugger.interpret(code))
    else
      try
        lock(evallock)
        withpath(nothing) do
          result = @errs eval(mod, :(ans = include_string($code, "console")))
          !isa(result,EvalError) && ends_with_semicolon(code) && (result = nothing)
          Base.invokelatest(render′, result)
        end
        unlock(evallock)
      catch e
        showerror(STDERR, e, catch_stacktrace())
      end
    end
  end
  return
end

handle("docs") do data
  @destruct [mod || "Main", word] = data
  docstring = @errs getdocs(mod, word)

  docstring isa EvalError && return Dict(:error => true)

  mtable = try getmethods(mod, word) catch [] end
  Dict(:error    => false,
       :type     => :dom,
       :tag      => :div,
       :contents =>  map(x -> render(Inline(), x), [docstring; mtable]))
end

handle("methods") do data
  @destruct [mod || "Main", word] = data
  mtable = @errs getmethods(mod, word)
  if isa(mtable, EvalError)
    Dict(:error => true, :items => sprint(showerror, mtable.err))
  else
    Dict(:items => [gotoitem(m) for m in mtable])
  end
end

getmethods(mod, word) = methods(getthing("$mod.$word"))

function getdocs(mod, word)
  if Symbol(word) in keys(Docs.keywords)
    eval(:(@doc($(Symbol(word)))))
  else
    include_string(getthing(mod), "@doc $word")
  end
end

function gotoitem(m::Method)
  _, link = view(m)
  sig = sprint(show, m)
  sig = sig[1:rsearch(sig, ')')]
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

function wsitem(name::Symbol, val)
  d(:name  => name,
    :value => render′(Inline(), val),
    :type  => wstype(val),
    :icon  => wsicon(val))
end

wsitem(mod::Module, name::Symbol) = wsitem(name, getfield(mod, name))

handle("workspace") do mod
  mod = getthing(mod)
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
