using Media
import REPL

using Logging: with_logger
using .Progress: JunoProgressLogger

ends_with_semicolon(x) = REPL.ends_with_semicolon(split(x,'\n',keepempty = false)[end])

withpath(f, path) =
  CodeTools.withpath(f, path == nothing || isuntitled(path) ? nothing : path)

const evallock = ReentrantLock()

handle("evalshow") do data
  @destruct [
    text,
    line,
    path,
    mod
  ] = data
  evalshow(text, line, path, mod)
  nothing
end

function evalshow(text, line, path, mod)
  fixjunodisplays()
  @dynamic let Media.input = Editor()
    mod = getmodule(mod)

    lock(evallock)
    result = hideprompt() do
      with_logger(JunoProgressLogger()) do
        withpath(path) do
          res = @errs include_string(mod, text, path, line)

          if res isa EvalError
              Base.showerror(IOContext(stderr, :limit => true), res)
          elseif res !== nothing && !ends_with_semicolon(text)
            display(res)
          end
        end
      end
    end
    unlock(evallock)

    Base.invokelatest() do
      display = Media.getdisplay(typeof(result), Media.pool(Editor()), default = Editor())
      !isa(result, EvalError) && ends_with_semicolon(text) && (result = nothing)
      display ≠ Editor() && result !== nothing && @ierrs render(display, result)
    end
  end
end

handle("eval") do data
  @destruct [
    text,
    line,
    path,
    mod,
    errorinrepl = :errorInRepl || false
  ] = data
  eval(text, line, path, mod, errorinrepl)
end

function eval(text, line, path, mod, errorinrepl = false)
  fixjunodisplays()
  @dynamic let Media.input = Editor()
    mod = getmodule(mod)

    lock(evallock)
    result = hideprompt() do
      with_logger(JunoProgressLogger()) do
        withpath(path) do
          res = @errs include_string(mod, text, path, line)
          if errorinrepl && res isa EvalError
            try
              Base.showerror(IOContext(stderr, :limit => true), res)
            catch err
              show(stderr, err)
            end
          end
          return res
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

# dummy handler for Revise compat
handle("evalrepl") do data
  @warn "Juno's evalrepl handler is deprecated."
end

handle("evalall") do data
  @destruct [
    code,
    mod = :module || nothing,
    path || "untitled"
  ] = data
  evalall(code, mod, path)
  nothing
end

function evalall(code, mod = nothing, path = "untitled")
  fixjunodisplays()
  @dynamic let Media.input = Editor()
    mod = if mod !== nothing
       getmodule(mod)
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
          catch err
            ee = EvalError(err, stacktrace(catch_backtrace()))

            # show error in REPL:
            Base.showerror(IOContext(stderr, :limit => true), ee)
            # show notification (if enabled in Atom):
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
end

handle("docs") do data
  @destruct [
    word,
    mod || "Main"
  ] = data
  docs(word, mod)
end

function docs(word, mod = "Main")
  docstring = @errs getdocs(mod, word)
  docstring isa EvalError && return Dict(:error => true)

  mtable = try getmethods(mod, word)
    catch e
      []
    end

  Dict(
    :error    => false,
    :type     => :dom,
    :tag      => :div,
    :contents =>  map(x -> render(Inline(), x), [docstring; mtable])
  )
end
