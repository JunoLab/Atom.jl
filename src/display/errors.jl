type EvalError
  err
  bt
end

@render i::Inline err::EvalError begin
  Text(sprint(showerror, err.err, err.bt))
end
