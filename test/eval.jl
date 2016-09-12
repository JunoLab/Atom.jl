import JSON
# mock a listener:
eval(Atom, parse("sock = IOBuffer()"))

# helper
readmsg() = JSON.parse(ascii(takebuf_array(Atom.sock)))
function symbol_to_string(d::Associative)
  d_new = similar(d)
  for k in keys(d)
    d_new[string(k)] = symbol_to_string(d[k])
  end
  d_new
end
symbol_to_string(x::Symbol) = string(x)
symbol_to_string(x) = x

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

# eval
# we can eval into Main and get the correct result back
eval_obj = Dict("text" => "sin(pi)", "line" => 1, "path" => pwd(), "mod" => "Main")
Atom.handlemsg(Dict("type" => "eval",
                    "callback" => (cb += 1)),
                    eval_obj)
@test readmsg() == ["cb", cb, symbol_to_string(Atom.render(Atom.Editor(), sin(pi)))]

# we can eval into a different module and have unqualified access to its members
eval_obj = Dict("text" => "sock", "line" => 1, "path" => pwd(), "mod" => "Atom")
Atom.handlemsg(Dict("type" => "eval",
                    "callback" => (cb += 1)),
                    eval_obj)
@test readmsg() == ["cb", cb, symbol_to_string(Atom.render(Atom.Editor(), Atom.sock))]

# we catch errors appropriately
eval_obj = Dict("text" => "notdefined", "line" => 1, "path" => pwd(), "mod" => "Atom")
Atom.handlemsg(Dict("type" => "eval",
                    "callback" => (cb += 1)),
                    eval_obj)
@test readmsg()[3]["type"] == "error"

# we execute the command in the correct file
eval_obj = Dict("text" => "@__FILE__", "line" => 1, "path" => normpath(joinpath(pwd(), "tests.jl")), "mod" => "Atom")
Atom.handlemsg(Dict("type" => "eval",
                    "callback" => (cb += 1)),
                    eval_obj)
@test readmsg() == ["cb", cb, symbol_to_string(Atom.render(Atom.Editor(), normpath(joinpath(pwd(), "tests.jl"))))]
