using SnoopCompile

@snoopi_bot BotConfig("Atom", blacklist = ["realpath′","restart_copyto_nonleaf!","allocatedinline"])


# template for exlcuding tests files from precompilation (kept for the record)
# using runtests except badfile
################################################################
# disabling inlcude badfile
# a1 = "include(\"badfile.jl\")"
#
# testText = Base.read("test/runtests.jl", String)
# testEdited = foldl(replace,
#                      (
#                       a1 => "#"*a1,
#                      ),
#                      init = testText)
# Base.write("test/runtests.jl", testEdited)
################################################################
# @snoopi_bot BotConfig("Atom", blacklist = ["realpath′"])
################################################################
# enabling back inlcude goto
# Base.write("test/runtests.jl", testText)
################################################################
# using runtests:
# @snoopi_bot "Atom"
