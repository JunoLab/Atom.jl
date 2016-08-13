type EvalError
  err
  bt
end

EvalError(err) = EvalError(err, [])

# @render Inline e::EvalError Text(sprint(Base.showerror, e.err, e.bt))

rendererr(err) = strong(".error-description", err)

function splitlink(path)
  m = match(r"^(.?:?[^:]*)(?::(\d+))$", path)
  m == nothing && return path, 0
  m.captures[1], parse(Int, m.captures[2])
end

function btlines(bt)
  isempty(bt) && return []
  trace = Base.stacktrace(bt)
  t_trace = map(trace) do frame
    (sprint(Base.StackTraces.show_spec_linfo, frame),
    string(frame.file),
    frame.line,
    frame.inlined ? " [inlined]" : "")
  end
  # clip stack traces
  internal_ind = findlast(t_trace) do t_frame
    ismatch(r"loading\.jl", t_frame[2]) &&
    ismatch(r"include_string", t_frame[1])
  end
  t_trace[1:internal_ind-1]
end

highlights(lines) =
  @>> lines filter(x->x[3]>0) map(x->d(:file=>fullpath(x[2]),:line=>x[3]))

highlights(e::EvalError) = highlights(btlines(e.bt))

function renderbt(ls)
  span(".error-trace",
       [div(".trace-entry",
        c(fade("in "), f, fade(" at "),
          render(Inline(), Copyable(baselink(loc, li))), fade(inlined)))
        for (f, loc, li, inlined) in ls])
end

function render(::Editor, e::EvalError)
  header = sprint(showerror, e.err)
  header = split(header, '\n')
  trace = btlines(e.bt)
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
                    Copyable(view, sprint(showerror, e.err, e.bt))),
    :highlights => highlights(e))
end

render(::Console, e::EvalError) =
  @msg result(render(Editor(), e))
