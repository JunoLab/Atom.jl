type EvalError
  err
  bt
end

rendererr(err) = strong(".error-description", sprint(showerror, err))

function btlines(bt, top_function::Symbol = :eval_user_input, set = 1:typemax(Int))
  @_ begin
    sprint(Base.show_backtrace, top_function, bt, set)
    split(_, "\n")
    map(strip, _)
    filter(x->!isempty(x), _)
    map(l -> match(r"^in (.*) at (.*)$", l), _)
    map(l -> (l.captures[1], l.captures[2]), _)
  end
end

function renderbt(ls)
  span(".error-trace",
       [div(".trace-entry", c(fade("in "), f, fade(" at "), baselink(loc))) for (f, loc) in ls])
end

@render i::Inline e::EvalError begin
  Tree(rendererr(e.err),
       [renderbt(btlines(e.bt))])
end
