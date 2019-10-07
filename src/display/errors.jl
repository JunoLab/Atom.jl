mutable struct EvalError{T}
  err::T
  trace::StackTrace
end

EvalError(err) = EvalError(err, StackTrace())

# Stacktrace fails on empty traces
EvalError(err, bt::Vector{Ptr{Nothing}}) = EvalError(err, isempty(bt) ? [] : stacktrace(bt))

macro errs(ex)
  :(try
      $(esc(ex))
    catch e
      EvalError(isa(e, LoadError) ? e.error : e, stacktrace(catch_backtrace()))
    end)
end

errtrace(e::EvalError) = errtrace(e.err, e.trace)

errmsg(e::EvalError) = errmsg(e.err)

function Base.show(io::IO, err::EvalError)
  print(io, errmsg(err))
  println(io)
  for frame in cliptrace(errtrace(err))
    show(io, frame)
    println(io)
  end
end

function Base.showerror(io::IO, err::EvalError)
  printstyled(io, "ERROR: "; bold=true, color=Base.error_color())
  Base.showerror(io, err.err, cliptrace(err.trace))
  println(io)
end

const MAX_STACKTRACE_LENGTH = 100
const STACKTRACE_END_LENGTH = 30

function cliptrace(trace::StackTrace)
  ind = findlast(frame -> (frame.func == :include_string &&
                           frame.file == Symbol(joinpath(".", "loading.jl"))) ||
                          (frame.func == :render′ &&
                           endswith(string(frame.file), joinpath(@__DIR__, "errors.jl"))), trace)
  trace = trace[1:(ind == nothing ? end : ind - 1)]
  if length(trace) > MAX_STACKTRACE_LENGTH
    splice!(trace, (MAX_STACKTRACE_LENGTH - STACKTRACE_END_LENGTH):(length(trace) - STACKTRACE_END_LENGTH))
  end
  trace
end

highlights(trace::StackTrace) =
  @>> trace filter(x->x.line > 0) map(x->d(:file=>fullpath(string(x.file)),:line=>x.line)) unique

highlights(e::EvalError) = highlights(e.trace)

function locationshading(file)
  f, p = expandpath(file)

  # error in base
  occursin(r"^base(/|\\).*", f) && return ".dark"
  # error in package
  # should probably be a bit smarter with figuring out if thats the actually package code
  occursin(joinpath(homedir(), ".julia"), p) && return ".medium"
  # error in "user code"
  return ".bright"
end

function renderbt(trace::StackTrace)
  span(".error-trace",
       [div(".trace-entry $(locationshading(string(frame.file)))",
            [fade("in "),
             frame.linfo == nothing || frame.linfo isa Core.CodeInfo ?
               string(frame.func) :
               replace(sprint(Base.show_tuple_as_call, frame.linfo.def.name, frame.linfo.specTypes),
                       r"\(.*\)$" => ""),
             fade(" at "),
             render(Inline(), Copyable(baselink(string(frame.file), frame.line))),
             fade(frame.inlined ? " <inlined>" : "")])
        for frame in reverse(trace)])
end

rendererr(err) = strong(".error-description", err)

function render(::Editor, e::EvalError)
  header = errmsg(e.err)
  header = split(header, '\n')
  trace = cliptrace(errtrace(e))
  view = if isempty(trace)
    if length(header) == 1
      rendererr(header[1])
    else
      Tree(rendererr(header[1]), [rendererr(join(header[2:end], '\n'))])
    end
  else
    Tree(rendererr(header[1]), [rendererr(join(header[2:end], '\n')); renderbt(trace)])
  end

  d(:type => :error,
    :view => render(Inline(),
                    Copyable(view, string(e))),
    :highlights => highlights(trace))
end

render(::Console, e::EvalError) =
  @msg result(render(Editor(), e))

mutable struct DisplayError
  obj
  err
end

errmsg(d::DisplayError) =
  "Error displaying $(typeof(d.obj)): $(errmsg(d.err))"

function render′(display, obj)
  try
    render(display, obj)
  catch e
    render(display, EvalError(DisplayError(obj, e), stacktrace(catch_backtrace())))
  end
end

render′(x) =
  render′(Media.getdisplay(Media.primarytype(x)), x)
