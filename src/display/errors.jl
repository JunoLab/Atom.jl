type EvalError
  err
  bt
end

# @render Inline e::EvalError Text(sprint(Base.showerror, e.err, e.bt))

rendererr(err) = strong(".error-description", err)

function splitlink(path)
  m = match(r"^(.?:?[^:]*)(?::(\d+))$", path)
  m == nothing && return path, 0
  m.captures[1], parse(Int, m.captures[2])
end

# TODO: don't work on the text
# TODO: clip traces so Atom/CodeTools doesn't show up

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
       [div(".trace-entry",
        c(fade("in "), f, fade(" at "),
          render(Inline(), Copyable(baselink(loc, li)))))
        for (f, loc, li) in ls])
end

function render(::Editor, e::EvalError; options = d())
  tmp = sprint(showerror, e.err)
  tmp = split(tmp, '\n')
  d(:type => :error,
    :view => render(Inline(),
                    Copyable(
                      Tree(rendererr(tmp[1]),
                           [rendererr(join(tmp[2:end], '\n')); renderbt(btlines(e.bt))]),
                      sprint(showerror, e.err, e.bt)),
                    options = options),
    :highlights => highlights(e))
end

render(::Console, e::EvalError; options = d()) =
  @msg result(render(Editor(), e, options = options))
