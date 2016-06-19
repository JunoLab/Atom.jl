# Manual Entry

export @step

function step(args...)
  global interp
  interp = enter_call_expr(nothing, :($(args...)()))
  tocall!(interp)
  debugmode(true)
  stepto(interp)
  return
end

macro step(ex)
  @capture(ex, f_(args__)) || error("Syntax: @enter f(...)")
  :(step($(esc(f)), $(map(esc, args)...)))
end
