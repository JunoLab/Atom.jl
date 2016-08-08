using CodeTools, LNR, Media, Requires

import CodeTools: getthing

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

macro errs(ex)
  :(try
      $(esc(ex))
    catch e
      EvalError(isa(e, LoadError) ? e.error : e, catch_backtrace())
    end)
end

withpath(f, path) =
  Requires.withpath(f, path == nothing || isuntitled(path) ? nothing : path)

handle("eval") do data
  @destruct [text, line, path, mod] = data
  mod = getthing(mod)

  result = @run begin
    @dynamic let Media.input = Editor()
      withpath(path) do
        @errs include_string(mod, text, path, line)
      end
    end
  end

  display = Media.getdisplay(typeof(result), Media.pool(Editor()), default = Editor())
  display ≠ Editor() && render(display, result)
  render(Editor(), result)
end

handle("evalall") do data
  @destruct [setmod = :module || nothing, path || "untitled", code] = data
  mod = Main
  if setmod ≠ nothing
    mod = getthing(setmod, Main)
  elseif isabspath(path)
    mod = getthing(CodeTools.filemodule(path), Main)
  end
  @run begin
    @dynamic let Media.input = Editor()
      withpath(path) do
        try
          include_string(mod, code, path)
        catch e
          ee = EvalError(e, catch_backtrace())
          render(Console(), ee)
          @msg error(d(:msg => "Error evaluating $(basename(path))",
                       :detail => sprint(showerror, e, ee.bt),
                       :dismissable => true))
        end
      end
    end
  end
  return
end

handle("evalrepl") do data
  @destruct [mode || nothing, code, mod || "Main"] = data
  mod = getthing(mod)
  if mode == "shell"
    code = "Base.repl_cmd(`$code`, STDOUT)"
  elseif mode == "help"
    code = "@doc $code"
  end
  if Debugger.isdebugging()
    render(Console(), @errs Debugger.interpret(code))
  else
    try
      @run begin
        @dynamic let Media.input = Console()
          withpath(nothing) do
            render(@errs eval(mod, :(ans = include_string($code))))
          end
        end
      end
    catch e
      showerror(STDERR, e, catch_backtrace())
    end
  end
  return
end

handle("docs") do data
  @destruct [mod || "Main", word] = data
  mod = getthing(mod)
  docstring = @errs include_string(mod, "@doc $word")
  mtable = try include_string(mod, "methods($word)") catch [] end
  out = [HTML(sprint(show, MIME"text/html"(), docstring)); mtable]
  isa(docstring, EvalError) ?
    d(:error    =>  true)   :
    d(:type     => :dom,
      :tag      => :div,
      :contents =>  map(x -> render(Editor(), x), out))
end

handle("methods") do data
  @destruct [mod || "Main", word] = data
  mod = include_string(mod)
  wordtype = try
    include_string("typeof($word)")
  catch
    Function
  end
  if wordtype == Function
    result = @errs include_string(mod, "methods($word)")
  elseif wordtype == DataType
    result = @errs include_string(mod, "methodswith($word)")
  end
  d(:result => render(Editor(), result))
end

ismacro(f::Function) = startswith(string(methods(f).mt.name), "@")

wstype(x) = nothing
wstype(::Module) = "module"
wstype(f::Function) = ismacro(f) ? "mixin" : "function"
wstype(::Type) = "type"
wstype(::Expr) = "mixin"
wstype(::Symbol) = "tag"
wstype(::AbstractString) = "property"
wstype(::Number) = "constant"
wstype(::Exception) = "tag"

wsicon(x) = nothing
wsicon(f::Function) = ismacro(f) ? "icon-mention" : nothing
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
wsnamed(name, T::DataType) = name == symbol(T.name)

function wsitem(name::Symbol, val)
  d(:name  => wsnamed(name, val) ? nothing : name,
    :value => render(Inline(), val),
    :type  => wstype(val),
    :icon  => wsicon(val))
end

wsitem(mod::Module, name::Symbol) = wsitem(name, getfield(mod, name))

handle("workspace") do mod
  mod = getthing(mod)
  ns = names(mod)
  # TODO: only filter out imported modules
  filter!(n -> !isa(getfield(mod, n), Module), ns)
  contexts = [d(:context => string(mod), :items => map(n -> wsitem(mod, n), ns))]
  if Debugger.isdebugging()
    prepend!(contexts, Debugger.contexts())
  end
  return contexts
end
