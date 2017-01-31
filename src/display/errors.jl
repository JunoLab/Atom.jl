import Juno: errtrace, errmsg

type EvalError{T}
  err::T
  trace::StackTrace
end

EvalError(err) = EvalError(err, [])

# Stacktrace fails on empty traces
EvalError(err, bt::Vector{Ptr{Void}}) = EvalError(err, isempty(bt) ? [] : stacktrace(bt))

errtrace(e::EvalError) = errtrace(e.err, e.trace)
errmsg(e::EvalError) = errmsg(e.err)

function Base.show(io::IO, err::EvalError)
  print(io, errmsg(err))
  println(io)
  for frame in errtrace(err)
    show(io, frame)
    println(io)
  end
end

function cliptrace(trace::StackTrace)
  ind = findlast(frame -> frame.func == :include_string &&
                          frame.file == Symbol(joinpath(".", "loading.jl")), trace)
  trace[1:(ind==0 ? end : ind-1)]
end

highlights(trace::StackTrace) =
  @>> trace filter(x->x.line > 0) map(x->d(:file=>fullpath(string(x.file)),:line=>x.line)) unique

highlights(e::EvalError) = highlights(e.trace)

function renderbt(trace::StackTrace)
  span(".error-trace",
       [div(".trace-entry",
            c(fade("in "), string(frame.func), fade(" at "),
              render(Inline(), Copyable(baselink(string(frame.file), frame.line)))))
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
    :highlights => highlights(e))
end

render(::Console, e::EvalError) =
  @msg result(render(Editor(), e))
