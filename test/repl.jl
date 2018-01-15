using Atom: didWriteToREPL

@test didWriteToREPL(() -> print(STDERR, "Atom REPL STDERR test")) == (nothing, true, false)
@test didWriteToREPL(() -> println("Atom REPL STDOUT test")) == (nothing, true, true)
@test didWriteToREPL(() -> print("Atom REPL STDOUT \n test")) == (nothing, true, false)
@test didWriteToREPL(() -> begin
    print("Atom REPL STDOUT test")
    print(STDERR, "foo\n")
end) == (nothing, true, true)
@test didWriteToREPL(() -> 1+1) == (2, false, false)
