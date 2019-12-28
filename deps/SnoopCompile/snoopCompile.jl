using SnoopCompile

@snoopiBot "Atom" begin
  using Atom

  # Use runtests.jl
  include(joinpath(dirname(dirname(pathof(Atom))), "test", "runtests.jl"))

  # Ues examples
end
