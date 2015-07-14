module AtomClient

using Lazy, JSON

global sock = nothing

isactive(sock::Nothing) = false
isactive(sock) = isopen(sock)

function connect(port)
  global sock = Base.connect(port)
  @schedule while isopen(sock)
    (t, data) = JSON.parse(sock)
    @show t data
  end
end

function msg(t, data)
  isactive(sock) || return
  println(sock, json(c(t, data)))
end

end # module
