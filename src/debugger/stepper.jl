import ASTInterpreter2
import DebuggerFramework: DebuggerState, execute_command, print_status, locinfo, eval_code, dummy_state
import ..Atom: fullpath, handle, @msg, wsitem, Inline, EvalError, Console
import Juno: Row, ProgressBar, Tree
using Media
using MacroTools

chan = nothing
state = nothing

isdebugging() = chan ≠ nothing

# entrypoint
function enter(arg)
  quote
    # FIXME: should use `qualifyASTInterpreter(ASTInterpreter2._make_stack(arg))`
    # instead, but I can't get that to work.
    let stack = $(make_stack(arg))
      Atom.Debugger.startdebugging(stack)
    end
  end
end

function make_stack(arg)
    arg = expand(arg)
    @assert isa(arg, Expr) && arg.head == :call
    kws = collect(filter(x->isexpr(x,:kw),arg.args))
    if !isempty(kws)
      args = Expr(:tuple,:(Core.kwfunc($(args[1]))),
        Expr(:call,Base.vector_any,mapreduce(
          x->[QuoteNode(x.args[1]),x.args[2]],vcat,kws)...),
        map(x->isexpr(x,:parameters)?QuoteNode(x):x,
          filter(x->!isexpr(x,:kw),arg.args))...)
    else
      args = Expr(:tuple,
        map(x->isexpr(x,:parameters)?QuoteNode(x):x, arg.args)...)
    end
    quote
        theargs = $(esc(args))
        stack = [Atom.Debugger.ASTInterpreter2.enter_call_expr(Expr(:call,theargs...))]
        Atom.Debugger.ASTInterpreter2.maybe_step_through_wrapper!(stack)
        stack[1] = Atom.Debugger.ASTInterpreter2.JuliaStackFrame(stack[1], Atom.Debugger.ASTInterpreter2.maybe_next_call!(stack[1]))
        stack
    end
end

function qualifyASTInterpreter(expr)
  postwalk(expr) do ex
    if @capture(ex, f_(xs__)) && startswith(string(f), "ASTInterpreter2")
      :($(Symbol("Atom.Debugger.", f))($(xs...)))
    else
      ex
    end
  end
end

# setup interpreter
function startdebugging(stack)
  # println(stack)
  global state = dummy_state(stack)
  global chan = Channel(0)

  debugmode(true)

  stepto(state)
  res = nothing

  try
    evalscope() do
      for val in chan
        if val == :nextline
          execute_command(state, state.stack[state.level], Val{:n}(), "n")
        elseif val == :stepexpr
            execute_command(state, state.stack[state.level], Val{:nc}(), "nc")
        elseif val == :stepin
          execute_command(state, state.stack[state.level], Val{:s}(), "s")
        elseif val == :finish
          execute_command(state, state.stack[state.level], Val{:finish}(), "finish")
        elseif typeof(val) <: Tuple && val[1] == :toline
          while locinfo(state.stack[state.level]).line < val[2]
            execute_command(state, state.stack[state.level], Val{:n}(), "n")
            length(state.stack) == 0 && break
          end
        else
          warn("Internal: Unknown debugger message $val.")
        end
        length(state.stack) == 0 && break
        stepto(state)
      end
    end
  catch e
    ee = EvalError(e, catch_stacktrace())
    render(Console(), ee)
  finally
    res = state.overall_result
    chan = nothing
    state = nothing
    debugmode(false)
  end
  res
end

# setup handlers for stepper commands
for cmd in [:nextline, :stepin, :stepexpr, :finish]
  handle(()->put!(chan, cmd), string(cmd))
end

handle((line)->put!(chan, (:toline, line)), "toline")

# notify the frontend that we start debugging now
debugmode(on) = @msg debugmode(on)

## Stepping

# perform step in frontend
function stepto(state::DebuggerState)
  loc = locinfo(state.stack[state.level])
  if loc == nothing
    file, line = ASTInterpreter2.determine_line_and_file(state.stack[state.level])[end]
  else
    file, line = loc.filepath, loc.line
  end
  stepto(Atom.fullpath(string(file)), line, stepview(nextstate(state)))
end
stepto(file, line, text) = @msg stepto(file, line, text)
stepto(::Void) = debugmode(false)

# return expression that will be evaluated next
function nextstate(state)
  frame = state.stack[state.level]
  expr = ASTInterpreter2.pc_expr(frame, frame.pc)
  isa(expr, Expr) && (expr = copy(expr))
  if isexpr(expr, :(=))
      expr = expr.args[2]
  end
  if isexpr(expr, :call) || isexpr(expr, :return)
      expr.args = map(var -> ASTInterpreter2.lookup_var_if_var(frame, var), expr.args)
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

function contexts(s::DebuggerState = state)
  cxt = []
  trace = ""
  for frame in reverse(state.stack)
    trace = string(trace, "/", frame.meth.name)
    c = Dict(:context => string("Debug: ", trace), :items => localvars(frame))
    push!(cxt, c)
  end
  cxt
end

function localvars(frame::ASTInterpreter2.JuliaStackFrame)
  items = []
  for i = 1:length(frame.locals)
    if !isnull(frame.locals[i])
      if frame.code.slotnames[i] == Symbol("#self#") && sizeof(get(frame.locals[i])) == 0
        continue
      end
      push!(items, wsitem(frame.code.slotnames[i], get(frame.locals[i], Undefined())))
    end
  end
  for i = 1:length(frame.sparams)
    push!(items, wsitem(frame.meth.sparam_syms[i], get(Nullable{Any}(frame.sparams[i]), Undefined())))
  end

  return items
end

type Undefined end
@render Inline u::Undefined span(".fade", "<undefined>")
Atom.wsicon(::Undefined) = "icon-circle-slash"

## Evaluation

function interpret(code::AbstractString, frame::DebuggerState = state)
  eval_code(state, state.stack[state.level], code)
end
