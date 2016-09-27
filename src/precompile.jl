const precomp = [
  ["cd", homedir()],
  [Dict(:callback=>1, :type=>:ping)],
  [Dict(:callback=>1, :type=>:evalrepl),Dict(:code=>2+2,:mod=>"Main",:mode=>"julia")],
  ["clearLazy", []],
  [Dict(:callback=>3,:type=>"workspace"),"Main"],
]

function precompile()
  server = listen(ip"127.0.0.1", 3000)
  task = @schedule @sync connect(3000)
  mock = accept(server)

  for msg in precomp
    println(sock, json(msg))
  end

  close(mock)
  wait(task)
end

Juno.isprecompiling() && precompile()
