using SnoopCompile

# using runtests except modules/goto
################################################################
# disabling inlcude modules/goto
a1 = "include(\"modules.jl\")"
a2 = "include(\"goto.jl\")"

testText = Base.read("test/runtests.jl", String)
testEdited = foldl(replace,
                     (
                      a1 => "#"*a1,
                      a2 => "#"*a2,
                     ),
                     init = testText)
Base.write("test/runtests.jl", testEdited)
################################################################
# BotConfig("Atom", blacklist = [" "," "])
@snoopiBot BotConfig("Atom")
################################################################
# enabling back inlcude modules/goto
Base.write("test/runtests.jl", testText)


################################################################
# using runtests:
# @snoopiBot "Atom"
