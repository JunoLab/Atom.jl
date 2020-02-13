# Atom

[![Build Status](https://travis-ci.org/JunoLab/Atom.jl.svg?branch=master)](https://travis-ci.org/JunoLab/Atom.jl) [![Docs](https://img.shields.io/badge/docs-latest-blue.svg)](https://JunoLab.github.io/JunoDocs.jl/latest) [![codecov](https://codecov.io/gh/JunoLab/Atom.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/JunoLab/Atom.jl)

This is the language server backend for [Juno](http://junolab.org/), the [Julia](http://julialang.org/) IDE. 

The frontend for certain exposed functionality (getting input, showing a selector widget etc.) is provided via [Juno.jl](https://github.com/JunoLab/Juno.jl), which is a much more lightweight (and pure Julia) dependency.

For documentation on how the communication between client and server is handled, head on over to the [developer documentation at atom-julia-client](https://github.com/JunoLab/atom-julia-client/blob/master/docs/communication.md).


## Note for developers

If any method signature has been changed after you modify the code base,
it may lead to cause an error in [the precompilation file](./src/precompile.jl)
when you precompile this package again.

It's okay to temporarily comment out the `_precompile_()` call in
[Atom.jl](./src/Atom.jl) until you satisfy with your changes,
and then error because of precompilation failure won't happen while editing.
(NOTE: don't comment `include("precompile.jl")`, otherwise it would break some testcase).

Finally you may need to run the following command and update the precompilation statements.

> at the root of this package directory

```bash
λ julia --project=. --color=yes scripts/generate_precompile.jl
```
