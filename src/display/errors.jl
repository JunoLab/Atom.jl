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
    map(l -> match(r"^(?:in (.*) at|(.*) from) (.*)$", l), _)
    map(l -> (@or(l.captures[1], l.captures[2]), l.captures[3]), _)
  end
end

function splitlink(path)
  m = match(r"^(.?:?[^:]*)(?::(\d+))$", path)
  m == nothing && return
  m.captures[1], parse(Int, m.captures[2])
end

highlights(lines) =
  @>> lines map(l->splitlink(l[2])) filter(x->x≠nothing) map(x->@d(:file=>fullpath(x[1]),:line=>x[2]))

highlights(e::EvalError) = highlights(btlines(e.bt))

function renderbt(ls)
  span(".error-trace",
       [div(".trace-entry", c(fade("in "), f, fade(" at "), baselink(loc))) for (f, loc) in ls])
end

render(i::Inline, e::EvalError; options = @d()) =
  @d(:type => :error,
     :view => render(i, Tree(rendererr(e.err),
                             [renderbt(btlines(e.bt))]), options = options),
     :highlights => highlights(e))

function write_plain(io::IO, arg)
  writemime(io, "text/plain", arg)
  takebuf_string(plain_buffer)
end

function write_plain(io::IO, arg::EvalError)
  println(io, sprint(showerror, arg.err))
  [println(io, "in "*string(f)*" at "*loc) for (f, loc) in btlines(arg.bt)]
  takebuf_string(io)
end
