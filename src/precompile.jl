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
  for p in 49152:65535
    s = try
      listen(ip"127.0.0.1", p)
    catch e
      # if EADDRINUSE, try the next port, otherwise rethrow
      if isa(e, Base.UVError) && e.code == -4091
        continue
      else
        rethrow(e)
      end
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
