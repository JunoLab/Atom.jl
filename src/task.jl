const runqueue = Channel()

@init @schedule while true
  f, c = take!(runqueue)
  try
    notify(c, f())
  catch e
    notify(c, e, error = true)
  end
end

function run_t(f)
  c = Condition()
  put!(runqueue, (f, c))
  wait(c)
end

macro run(ex)
  :(run_t(()->$(esc(ex))))
end
