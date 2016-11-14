const precomp = [
  ["cd", homedir()],
  [Dict(:callback=>1, :type=>:ping)],
  [Dict(:callback=>1, :type=>:evalrepl),Dict(:code=>2+2,:mod=>"Main",:mode=>"julia")],
  ["clearLazy", []],
  [Dict(:callback=>3,:type=>"workspace"),"Main"],
]

function precompile()
  # use an ephemeral port for the mock server
  local port, server
  for p in 49160:65500
    s = try
      listen(ip"127.0.0.1", p)
    catch
      # this should not catch all errors, but `listen` can error with a generic
      # error if `bind` doesn't succeed and who knows where else...
      continue
    end
    server = s
    port = p
    break
  end

  task = @schedule @sync connect(port)
  mock = accept(server)

  for msg in precomp
    println(sock, json(msg))
  end

  close(mock)
  wait(task)
  global sock = nothing
end

Juno.isprecompiling() && precompile()
