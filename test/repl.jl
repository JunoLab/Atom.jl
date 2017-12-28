@test Atom.didWriteToREPL(() -> print(STDERR, "Atom REPL STDERR test")) == (nothing, true)
@test Atom.didWriteToREPL(() -> println("Atom REPL STDOUT test")) == (nothing, true)
@test Atom.didWriteToREPL(() -> 1+1) == (2, false)
