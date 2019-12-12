using SnoopCompile

@snoopiBot "MatLang" begin
  using Atom, Pkg

  # Use runtests.jl
  include(joinpath(dirname(dirname(pathof(Atom))), "test", "runtests.jl"))

  # Ues examples
end
