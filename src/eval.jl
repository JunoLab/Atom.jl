using Media
import REPL

using Logging: with_logger
using .Progress: JunoProgressLogger

ends_with_semicolon(x) = REPL.ends_with_semicolon(split(x,'\n',keepempty = false)[end])

withpath(f, path) =
  CodeTools.withpath(f, path == nothing || isuntitled(path) ? nothing : path)

const eval_channel_in = Channel(1)
const eval_channel_out = Channel(1)
const eval_backend_task = Ref{Any}(nothing)
const is_backend_working = Ref{Bool}(false)

function is_evaling()
  return is_backend_working[] || inREPL[]
end

function run_with_backend(f, args...)
  put!(eval_channel_in, (f, args))
  r = take!(eval_channel_out)
  if r isa EvalError || r isa ErrorException
    render′(Editor(), r)
  else
    update_project()
    # update_workspace()
    r
  end
end

function start_eval_backend()
  global eval_backend_task[] = @async begin
    Base.sigatomic_begin()
    while true
      try
        f, args = take!(eval_channel_in)
        Base.sigatomic_end()
        is_backend_working[] = true
        res = @errs Base.invokelatest(f, args...)
        is_backend_working[] = false
        Base.sigatomic_begin()
        put!(eval_channel_out, res)
      catch err
        put!(eval_channel_out, err)
      finally
        is_backend_working[] = false
      end
    end
    Base.sigatomic_end()
  end
end

handle("evalshow") do data
  @destruct [
    text,
    line,
    path,
    mod
  ] = data

  run_with_backend(evalshow, text, line, path, mod)
  nothing
end

function evalshow(text, line, path, mod)
  fixjunodisplays()
  @dynamic let Media.input = Editor()
    mod = getmodule(mod)

    result = hideprompt() do
      with_logger(JunoProgressLogger()) do
        withpath(path) do
          args = @static VERSION ≥ v"1.5" ? (REPL.softscope, mod, text, path, line) : (mod, text, path, line)
          res = @errs include_string(args...)

          Base.invokelatest() do
            if res isa EvalError
              Base.showerror(IOContext(stderr, :limit => true), res)
            elseif res !== nothing && !ends_with_semicolon(text)
              display(res)
            end
          end

          res
        end
      end
    end

    Base.invokelatest() do
      display = Media.getdisplay(typeof(result), Media.pool(Editor()), default = Editor())
      !isa(result, EvalError) && ends_with_semicolon(text) && (result = nothing)
      if display ≠ Editor() && result !== nothing
        @ierrs render(display, result)
      end
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
  run_with_backend(eval, text, line, path, mod, errorinrepl)
end

function eval(text, line, path, mod, errorinrepl = false)
  fixjunodisplays()
  @dynamic let Media.input = Editor()
    mod = getmodule(mod)

    result = hideprompt() do
      with_logger(JunoProgressLogger()) do
        withpath(path) do
          args = @static VERSION ≥ v"1.5" ? (REPL.softscope, mod, text, path, line) : (mod, text, path, line)
          res = @errs include_string(args...)
          if errorinrepl && res isa EvalError
            Base.invokelatest() do
              try
                Base.showerror(IOContext(stderr, :limit => true), res)
              catch err
                show(stderr, err)
              end
            end
          end
          return res
        end
      end
    end

    Base.invokelatest() do
      !isa(result, EvalError) && ends_with_semicolon(text) && (result = nothing)
      @ierrs displayandrender(result)
    end
  end
end

# dummy handler for Revise compat
handle("evalrepl") do data
  @warn("""
    Juno's evalrepl handler is deprecated.
    """, _id="evalrepl", maxlog=1)
end

handle("evalall") do data
  @destruct [
    code,
    mod = :module || nothing,
    path || "untitled"
  ] = data
  run_with_backend(evalall, code, mod, path)
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

    hideprompt() do
      with_logger(JunoProgressLogger()) do
        withpath(path) do
          result = nothing
          try
            result = include_string(mod, code, path)
          catch err
            ee = EvalError(err, stacktrace(catch_backtrace()))

            # show error in REPL:
            Base.invokelatest() do
              Base.showerror(IOContext(stderr, :limit => true), ee)
              # show notification (if enabled in Atom):
              @msg error(d(:msg => "Error evaluating $(basename(path))",
                           :detail => string(ee),
                           :dismissable => true))
            end
          end

          Base.invokelatest() do
            @ierrs displayandrender(result)
          end
        end
      end
    end
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
