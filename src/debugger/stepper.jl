using JuliaInterpreter: pc_expr, moduleof, linenumber, extract_args, debug_command,
                        root, caller, whereis, get_return, nstatements, @lookup, Frame
import JuliaInterpreter
import ..Atom: fullpath, handle, @msg, wsitem, Inline, EvalError, Console, display_error
import Juno: Row, Tree
import REPL
using Media
using MacroTools

mutable struct DebuggerState
  frame::Union{Nothing, Frame}
  result
end
DebuggerState(frame::Frame) = DebuggerState(frame, nothing)
DebuggerState() = DebuggerState(nothing, nothing)

const chan = Ref{Union{Channel, Nothing}}()
const STATE = DebuggerState()

isdebugging() = isassigned(chan) && chan[] !== nothing

# entrypoint
function enter(mod, arg)
  quote
    let frame = $(_make_frame(mod, arg))
      $(@__MODULE__).startdebugging(frame)
    end
  end
end

function _make_frame(mod, arg)
    args = try
      extract_args(mod, arg)
    catch e
      return :(throw($e))
    end
    quote
      theargs = $(esc(args))
      frame = $(@__MODULE__).JuliaInterpreter.enter_call_expr(Expr(:call, theargs...))
      $(@__MODULE__).JuliaInterpreter.maybe_step_through_wrapper!(frame)
      $(@__MODULE__).JuliaInterpreter.maybe_next_call!(frame)
      frame
    end
end

# setup interpreter
function startdebugging(frame)
  global STATE.frame = frame
  global chan[] = Channel(0)

  debugmode(true)
  if Atom.isREPL()
    # FIXME: Should get rid of the second code path (see comment in repl.jl).
    if Atom.inREPL[]
      t = @async debugprompt()
    else
      Atom.changeREPLprompt("debug> ", color="\e[38;5;166m")
    end
  end

  stepto(frame)
  res = nothing

  try
    evalscope() do
      for val in chan[]
        ret = if val == :nextline
          debug_command(frame, :n)
        elseif val == :stepexpr
          debug_command(frame, :nc)
        elseif val == :stepin
          debug_command(frame, :s)
        elseif val == :finish
          debug_command(frame, :finish)
        elseif val isa Tuple && val[1] == :toline && val[2] isa Int
          method = frame.framecode.scope
          @assert method isa Method
          # set temporary breakpoint
          bp = JuliaInterpreter.breakpoint(method, val[2])
          _ret = debug_command(frame, :finish)
          # and remove it again
          JuliaInterpreter.remove(bp)
          _ret
        else
          warn("Internal: Unknown debugger message $val.")
        end
        
        if ret === nothing
          STATE.result = res = JuliaInterpreter.get_return(root(frame))
          break
        else
          # STATE.frame = frame = JuliaInterpreter.maybe_step_through_wrapper!(ret[1])
          STATE.frame = frame = ret[1]
          JuliaInterpreter.maybe_next_call!(frame)
          stepto(frame)
        end
      end
    end
  catch err
    if Atom.isREPL()
      display_error(stderr, err, stacktrace(catch_backtrace()))
    else
      render(Console(), EvalError(e, catch_stacktrace()))
    end
  finally
    chan[] = nothing
    debugmode(false)

    if Atom.isREPL()
      if Atom.inREPL[]
        istaskdone(t) || schedule(t, InterruptException(); error=true)
        print("\r                        \r")
      else
        print("\r                        \r")
        Atom.changeREPLprompt(Atom.juliaprompt, color = :green, write = false)
      end
    end
  end
  res
end

using REPL
function debugprompt()
  try
    panel = REPL.LineEdit.Prompt("debug> ";
              prompt_prefix="\e[38;5;166m",
              prompt_suffix="\e[0m",
              on_enter = s -> true)

    panel.on_done = (s, buf, ok) -> begin
      Atom.msg("working")

      line = String(take!(buf))

      isempty(line) && return true

      if !ok
        REPL.LineEdit.transition(s, :abort)
        REPL.LineEdit.reset_state(s)
        return false
      end

      try
        r = Atom.JunoDebugger.interpret(line)
        r ≠ nothing && display(r)
        println()
      catch err
        display_error(stderr, err, stacktrace(catch_backtrace()))
      end

      Atom.msg("doneWorking")
      Atom.msg("updateWorkspace")

      return true
    end

    REPL.run_interface(Base.active_repl.t, REPL.LineEdit.ModalInterface([panel]))
  catch e
    e isa InterruptException || rethrow(e)
  end
end

# setup handlers for stepper commands
for cmd in [:nextline, :stepin, :stepexpr, :finish]
  handle(()->put!(chan[], cmd), string(cmd))
end

handle((line)->put!(chan[], (:toline, line)), "toline")

# notify the frontend that we start debugging now
debugmode(on) = @msg debugmode(on)

## Stepping

# perform step in frontend
function stepto(frame::Frame)
  file, line = JuliaInterpreter.whereis(frame)
  stepto(Atom.fullpath(string(file)), line, stepview(nextstate(frame)))
end
stepto(state::DebuggerState) = stepto(state.frame)
stepto(file, line, text) = @msg stepto(file, line, text)
stepto(::Nothing) = debugmode(false)

# return expression that will be evaluated next
nextstate(state::DebuggerState) = nextstate(state.frame)
function nextstate(frame::Frame)
  maybe_quote(x) = (isa(x, Expr) || isa(x, Symbol)) ? QuoteNode(x) : x

  expr = pc_expr(frame)
  isa(expr, Expr) && (expr = copy(expr))
  if isexpr(expr, :(=))
      expr = expr.args[2]
  end
  if isexpr(expr, :call) || isexpr(expr, :return)
    for i in 1:length(expr.args)
      val = try
          @lookup(frame, expr.args[i])
      catch err
          err isa UndefVarError || rethrow(err)
          expr.args[i]
      end
      expr.args[i] = maybe_quote(val)
    end
  end
  expr
end

function stepview(ex)
  out = if @capture(ex, f_(as__))
    Row(span(".syntax--support.syntax--function", string(typeof(f).name.mt.name)),
             text"(", interpose(as, text", ")..., text")")
  elseif @capture(ex, x_ = y_)
    Row(Text(string(x)), text" = ", y)
  elseif @capture(ex, return x_)
    Row(span(".syntax--support.syntax--keyword", "return "), x)
  else
    Text(string(ex))
  end
  render(Inline(), out)
end

function evalscope(f)
  try
    @msg doneWorking()
    unlock(Atom.evallock)
    f()
  finally
    lock(Atom.evallock)
    @msg working()
  end
end

## Workspace
function contexts(s::DebuggerState = STATE)
  s.frame === nothing && return []
  ctx = []
  trace = ""
  frame = root(s.frame)
  while frame ≠ nothing
    trace = string(trace, "/", frame.framecode.scope isa Method ?
                                frame.framecode.scope.name : "???")
    c = Dict(:context => string("Debug: ", trace), :items => localvars(frame))
    push!(ctx, c)

    frame = frame.callee
  end
  reverse(ctx)
end

function localvars(frame)
  vars = JuliaInterpreter.locals(frame)
  items = []
  for v in vars
      v.name == Symbol("#self#") && (isa(v.value, Type) || sizeof(v.value) == 0) && continue
      push!(items, wsitem(String(v.name), v.value))
  end
  return items
end

struct Undefined end
@render Inline u::Undefined span(".fade", "<undefined>")
Atom.wsicon(::Undefined) = "icon-circle-slash"

## Evaluation
function interpret(code::AbstractString, s::DebuggerState = STATE)
  s.frame === nothing && return
  eval_code(s.frame, code)
end

# copied from https://github.com/JuliaDebug/Debugger.jl/blob/master/src/repl.jl
function eval_code(frame::Frame, command::AbstractString)
    expr = Base.parse_input_line(command)
    isexpr(expr, :toplevel) && (expr = expr.args[end])
    # see https://github.com/JuliaLang/julia/issues/31255 for the Symbol("") check
    vars = filter(v -> v.name != Symbol(""), JuliaInterpreter.locals(frame))
    res = gensym()
    eval_expr = Expr(:let,
        Expr(:block, map(x->Expr(:(=), x...), [(v.name, v.value) for v in vars])...),
        Expr(:block,
            Expr(:(=), res, expr),
            Expr(:tuple, res, Expr(:tuple, [v.name for v in vars]...))
        ))
    eval_res, res = Core.eval(moduleof(frame), eval_expr)
    j = 1
    for (i, v) in enumerate(vars)
        if v.isparam
            frame.framedata.sparams[j] = res[i]
            j += 1
        else
            frame.framedata.locals[frame.framedata.last_reference[v.name]] = Some{Any}(res[i])
        end
    end
    eval_res
end
