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
      EvalError(e.error, catch_backtrace())
    end)
end

const evallock = ReentrantLock()

function Base.lock(f::Function, l::ReentrantLock)
  lock(l)
  try return f()
  finally unlock(l) end
end

withpath(f, path) =
  Requires.withpath(f, path == nothing || isuntitled(path) ? nothing : path)

handle("eval") do data
  @destruct [text, line, path, mod] = data
  mod = getthing(mod)
  lock(evallock) do
    @dynamic let Media.input = Editor()
      result = withpath(path) do
        @errs include_string(mod, text, path, line)
      end

      display = Media.getdisplay(typeof(result), default = Editor())
      display ≠ Editor() && render(display, result)
      render(Editor(), result)
     end
   end
end

handle("evalall") do data
  lock(evallock) do
    @dynamic let Media.input = Editor()
      @destruct [setmod = :module || nothing, path || "untitled", code] = data
      mod = Main
      if setmod ≠ nothing
        mod = getthing(setmod, Main)
      elseif isabspath(path)
        mod = getthing(CodeTools.filemodule(path), Main)
      end
      try
        withpath(path) do
          include_string(mod, code, path)
        end
      catch e
        @msg error(d(:msg => "Error evaluating $(basename(path))",
                     :detail => sprint(showerror, e, catch_backtrace()),
                     :dismissable => true))
      end
    end
    return
  end
end

handle("evalrepl") do data
  lock(evallock) do
    @dynamic let Media.input = Console()
      @destruct [mode || nothing, code, mod || "Main"] = data
      mod = getthing(mod)
      if mode == "shell"
        code = "run(`$code`)"
      elseif mode == "help"
        code = "@doc $code"
      end
      try
        withpath(nothing) do
          render(@errs eval(mod, :(include_string($code))))
        end
      catch e
        showerror(STDERR, e, catch_backtrace())
      end
      return
    end
  end
end

handle("docs") do data
  @destruct [mod || "Main", word] = data
  mod = include_string(mod)
  result = @errs include_string(mod, "@doc $word")
  d(:result => render(Editor(), result))
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
  @d(:result  => method_obj(result), 
     :error   => typeof(result)==EvalError ? true : false)
end
