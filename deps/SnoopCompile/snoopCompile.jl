using SnoopCompile

@snoopiBot "Atom" begin
  using Atom, Pkg

  # Use runtests.jl
  Pkg.test("Atom")

  # include(joinpath(dirname(dirname(pathof(Atom))), "test", "runtests.jl"))

  # Ues examples
end
