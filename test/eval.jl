import JSON
# mock a listener:
Core.eval(Atom, Meta.parse("sock = IOBuffer()"))
readmsg() = JSON.parse(String(take!(Atom.sock)))

# callback count
cb = 0

# check the different message handlers:
# pingpong
Atom.handlemsg(Dict("type" => "ping",
                    "callback" => (cb += 1)))
@test readmsg() == ["cb", cb, "pong"]

# echo
Atom.handlemsg(Dict("type" => "echo",
                    "callback" => (cb += 1)),
                    "echome!")
@test readmsg() == ["cb", cb, "echome!"]

# cd
old_path = pwd()
Atom.handlemsg(Dict("type" => "cd",
                    "callback" => (cb += 1)),
                    joinpath(old_path, ".."))
@test readmsg() == ["cb", cb, nothing]
@test pwd() == realpath(joinpath(old_path, ".."))
cd(old_path)

# evalsimple
Atom.handlemsg(Dict("type" => "evalsimple",
                    "callback" => (cb += 1)),
                    "1+1")
@test readmsg() == ["cb", cb, 2]

Atom.handlemsg(Dict("type" => "evalsimple",
                    "callback" => (cb += 1)),
                    "sin(pi)")
@test readmsg() == ["cb", cb, sin(pi)]
