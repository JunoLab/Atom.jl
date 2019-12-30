using SnoopCompile

# using runtests:
# @snoopiBot "Atom"
# using runtests except modules/goto
################################################################
# disabling inlcude modules/goto
a1 = "include(\"modules.jl\")"
a2 = "include(\"goto.jl\")"

file = open("test/runtests.jl","r")
testText = Base.read(file, String)
close(file)
testEdited = foldl(replace,
                     (
                      a1 => "#"*a1,
                      a2 => "#"*a2,
                     ),
                     init = testText)
file = open("test/runtests.jl","w")
Base.write(file, testEdited)
close(file)
################################################################
println("Examples/Tests infer benchmark")
@snoopiBot "Atom"
################################################################

# enabling back inlcude modules/goto
file = open("test/runtests.jl","w")
Base.write(file, testText)
close(file)
