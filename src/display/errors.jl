type EvalError
  err
  bt
end

# @render Inline e::EvalError Text(sprint(Base.showerror, e.err, e.bt))

rendererr(err) = strong(".error-description", err)

function splitlink(path)
  m = match(r"^(.?:?[^:]*)(?::(\d+))$", path)
  m == nothing && return path, -1
  m.captures[1], parse(Int, m.captures[2])
end

# TODO: don't work on the text

function btlines(bt, top_function::Symbol = :eval_user_input, set = 1:typemax(Int))
  @_ begin
    sprint(Base.show_backtrace, top_function, bt, set)
    split(_, "\n")
    map(strip, _)
    filter(x->!isempty(x), _)
    map(l -> match(r"^(?:in (.*) at|(.*) from) (.*)$", l), _)
    map(l -> (@or(l.captures[1], l.captures[2]), splitlink(l.captures[3])...), _)
  end
end

highlights(lines) =
  @>> lines filter(x->x[3]>0) map(x->d(:file=>fullpath(x[2]),:line=>x[3]))

highlights(e::EvalError) = highlights(btlines(e.bt))

function renderbt(ls)
  span(".error-trace",
       [div(".trace-entry", c(fade("in "), f, fade(" at "), render(Inline(), baselink(loc, li)))) for (f, loc, li) in ls])
end

function render(i::Inline, e::EvalError; options = d())
  tmp = sprint(showerror, e.err)
  tmp = split(tmp, '\n')
  d(:type => :error,
     :view => render(i, Tree(rendererr(tmp[1]),
                             [rendererr(join(tmp[2:end], '\n')); renderbt(btlines(e.bt))]), options = options),
     :highlights => highlights(e))
end
