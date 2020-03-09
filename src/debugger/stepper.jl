using JuliaInterpreter: pc_expr, extract_args, debug_command, root, caller,
                        whereis, get_return, @lookup, Frame
import JuliaInterpreter
import ..Atom: fullpath, handle, @msg, Inline, display_error, hideprompt, getmodule
import Juno: Row

mutable struct DebuggerState
  frame::Union{Nothing, Frame}
  broke_on_error::Bool
  level::Int
end
DebuggerState(frame::Frame) = DebuggerState(frame, false, 1)
DebuggerState() = DebuggerState(nothing, false, 1)

function active_frame(state::DebuggerState)
  frame = state.frame
  for i in 1:(stacklength(state) - state.level - 1)
    frame = caller(frame)
  end
  @assert frame !== nothing
  return frame
end

stacklength(state::DebuggerState) = stacklength(state.frame)
stacklength(::Nothing) = 0
function stacklength(frame::Frame)
  s = 0
  while frame !== nothing
    s += 1
    frame = caller(frame)
  end
  return s
end

const chan = Ref{Union{Channel, Nothing}}()
const STATE = DebuggerState()

isdebugging() = isassigned(chan) && chan[] !== nothing

maybe_quote(x) = (isa(x, Expr) || isa(x, Symbol)) ? QuoteNode(x) : x

check_is_call(arg) = !(arg isa Expr && arg.head == :call) && throw(ArgumentError("@enter and @run must be applied to a function call"))

# entrypoint
function enter(mod, arg; initial_continue = false)
  check_is_call(arg)
  quote
    let frame = $(_make_frame(mod, arg))
      ret, _ = $(@__MODULE__).startdebugging(frame, $(initial_continue))
      ret
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
    if frame !== nothing
      frame = $(@__MODULE__).JuliaInterpreter.maybe_step_through_kwprep!(frame)
      if frame !== nothing
        $(@__MODULE__).JuliaInterpreter.maybe_step_through_wrapper!(frame)
      end
    end
  end
end

function add_breakpoint(bp)
  cond = bp["condition"]
  cond = cond === nothing ? cond : Meta.parse(cond)
  JuliaInterpreter.breakpoint(bp["file"], bp["line"], cond)
end

function debug_file(mod, text, path, should_step, line_offset = 0)
  mod = getmodule(mod)

  hideprompt() do
    local expr, exprs
    try
      expr = MacroTools.postwalk(Base.parse_input_line(text, filename = path)) do x
        # NOTE: correct line numbers using line offset for debugging a block or cell
        if x isa LineNumberNode
          return LineNumberNode(x.line + line_offset, x.file)
        end
        return x
      end
      exprs, _ = JuliaInterpreter.split_expressions(mod, expr; filename = path)
    catch err
      println(stderr)
      Base.showerror(stderr, ErrorException("Error while parsing file or runtime error."), [])
      println(stderr)
      return
    end

    lc = should_step ? :stepexpr : :continue

    debugmode(true)

    for (i, (mod, ex)) in enumerate(exprs)
      lc == :stop && break

      temp_bps = add_breakpoint.(Atom.rpc("getFileBreakpoints"))

      frame = JuliaInterpreter.prepare_thunk(mod, ex)

      _, lc = Base.invokelatest(startdebugging,
        frame,
        lc == :continue || lc == nothing,
        istoplevel = true,
        toggle_ui = false
      )

      JuliaInterpreter.remove.(temp_bps)
    end

    debugmode(false)

    nothing
  end
end

# setup interpreter
function startdebugging(
    frame,
    initial_continue = false;
    istoplevel = false,
    toggle_ui = true,
  )
  if frame === nothing
    error("failed to enter the function, perhaps it is set to run in compiled mode")
  end
  STATE.frame = frame
  STATE.broke_on_error = false
  chan[] = Channel(0)

  temp_bps = add_breakpoint.(Atom.rpc("getFileBreakpoints"))

  res = nothing
  repltask = nothing
  lastcommand = nothing

  try
    evalscope() do
      if initial_continue && !JuliaInterpreter.shouldbreak(frame, frame.pc)
        ret = debug_command(_compiledMode[], frame, :c, true)
        if ret === nothing
          return res = JuliaInterpreter.get_return(root(frame))
        end
        STATE.frame = frame = ret[1]
        pc = ret[2]

        if pc isa JuliaInterpreter.BreakpointRef && pc.err !== nothing
          STATE.broke_on_error = true
          Base.display_error(stderr, ret[2].err, [])
        end
      end

      JuliaInterpreter.maybe_next_call!(frame, istoplevel)

      toggle_ui && debugmode(true)
      repltask = @async debugprompt()

      stepto(frame)

      # make sure we're at the bottom of the callstack initially
      STATE.level = stacklength(STATE) - 1

      for val in chan[]
        lastcommand = val
        if val == :stop
          return nothing
        end

        # remove all file/line breakpoints
        JuliaInterpreter.remove.(temp_bps)
        # and re-add them to get changes from frontend
        temp_bps = add_breakpoint.(Atom.rpc("getFileBreakpoints"))

        if STATE.broke_on_error
          printstyled(stderr, "Cannot step after breaking on error\n"; color=Base.error_color())
          continue
        end

        ret = if val == :nextline
          debug_command(_compiledMode[], frame, :n, true)
        elseif val == :stepexpr
          debug_command(_compiledMode[], frame, :nc, true)
        elseif val == :stepin
          debug_command(_compiledMode[], frame, :s, true)
        elseif val == :finish
          debug_command(_compiledMode[], frame, :finish, true)
        elseif val == :continue
          debug_command(_compiledMode[], frame, :c, true)
        elseif val isa Tuple && val[1] == :toline && val[2] isa Int
          method = frame.framecode.scope
          @assert method isa Method
          # set temporary breakpoint
          bp = JuliaInterpreter.breakpoint(method, val[2])
          _ret = debug_command(_compiledMode[], frame, :finish, true)
          # and remove it again
          JuliaInterpreter.remove(bp)
          _ret
        else
          warn("Internal: Unknown debugger message $val.")
        end

        if ret === nothing
          res = JuliaInterpreter.get_return(root(frame))
          break
        else
          STATE.frame = frame = ret[1]
          STATE.level = stacklength(STATE) - 1
          pc = ret[2]
          if pc isa JuliaInterpreter.BreakpointRef && pc.err !== nothing
            STATE.broke_on_error = true
            display_error(stderr, pc.err, [])
          end

          JuliaInterpreter.maybe_next_call!(frame)
          is_toplevel_return(frame) && break

          stepto(frame)
        end
      end
    end
  catch err
    display_error(stderr, err, stacktrace(catch_backtrace()))
  finally
    JuliaInterpreter.remove.(temp_bps)
    chan[] = nothing
    toggle_ui && debugmode(false)
    if repltask ≠ nothing
      istaskdone(repltask) || schedule(repltask, InterruptException(); error=true)
    end
  end
  res, lastcommand
end

is_toplevel_return(frame) = frame.framecode.scope isa Module && isexpr(pc_expr(frame), :return)

# setup handlers for stepper commands
for cmd in [:nextline, :stepin, :stepexpr, :finish, :stop, :continue]
  handle(()->put!(chan[], cmd), string(cmd))
end
handle((line)->put!(chan[], (:toline, line)), "toline")

handle(debug_file, "debugfile")

# notify the frontend that we start debugging now
function debugmode(on)
  @msg debugmode(on)
  @msg doneWorking()
end

## Stepping

# perform step in frontend
function stepto(frame::Frame, level = stacklength(STATE)-1)
  file, line = JuliaInterpreter.whereis(frame)
  file = Atom.fullpath(string(file))

  @msg stepto(file, line, stepview(nextstate(frame)), moreinfo(file, line, frame, level))
end
stepto(state::DebuggerState) = stepto(state.frame, state.level)
stepto(::Nothing) = debugmode(false)

handle("setStackLevel") do level
  with_error_message() do
    level = level isa String ? parseInt(level) : level
    STATE.level = level
    stepto(active_frame(STATE), level)
    nothing
  end
end

function moreinfo(file, line, frame, level)
  info = Dict()
  info["shortpath"], _ = Atom.expandpath(file)
  info["line"] = line
  info["level"] = level
  info["stack"] = stack(frame)
  info["moreinfo"] = get_code_around(file, line, frame)
  return info
end

function stack(frame)
  ctx = []
  frame = root(frame)
  level = 0
  while frame ≠ nothing
    method = frame.framecode.scope

    name = sprint(show, "text/plain", method)
    name = replace(name, r" in .* at .*$" => "")
    name = replace(name, r" where .*$" => "")

    file, line = JuliaInterpreter.whereis(frame)
    file = Atom.fullpath(string(file))
    shortpath, _ = Atom.expandpath(file)
    c = Dict(
      :level => level,
      :name => name,
      :line => line,
      :file => file,
      :shortpath => shortpath
    )
    pushfirst!(ctx, c)
    level += 1
    frame = frame.callee
  end
  ctx
end

"""
    get_code_around(file, line, frame; around = 3)

Get source code/CodeInfo around the currently active line in `frame`.
"""
function get_code_around(file, line, frame; around = 3)
  if isfile(file)
    lines = readlines(file)
  else
    src = JuliaInterpreter.copy_codeinfo(frame.framecode.src)
    JuliaInterpreter.replace_coretypes!(src; rev = true)
    lines = JuliaInterpreter.framecode_lines(src)

    line = convert(Int, frame.pc[])
  end
  firstline = max(1, line - around)
  lastline = min(length(lines), line + around)

  return (
    code = join(lines[firstline:lastline], '\n'),
    firstline = firstline,
    lastline = lastline,
    currentline = line
  )
end

# return expression that will be evaluated next
nextstate(state::DebuggerState) = nextstate(state.frame)
function nextstate(frame::Frame)
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
    fname = typeof(f).name.mt.name
    if Base.isoperator(fname)
      Row(interpose(as, span(".syntax--support.syntax--function", string(" ", fname, " ")))...)
    else
      Row(span(".syntax--support.syntax--function", string(fname)),
        text"(", interpose(as, text", ")..., text")")
    end
  elseif @capture(ex, x_ = y_)
    Row(Text(string(x)), text" = ", y)
  elseif @capture(ex, return x_)
    Row(span(".syntax--support.syntax--keyword", "return "), x)
  else
    Text(repr(ex))
  end
  Atom.render′(Atom.Inline(), out)
end

function evalscope(f)
  locked = islocked(Atom.evallock)
  try
    @msg doneWorking()
    locked && unlock(Atom.evallock)
    f()
  finally
    locked && lock(Atom.evallock)
    @msg working()
  end
end
