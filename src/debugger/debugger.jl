function enter(mod, ex; initial_continue = false)
  if isdebugging()
    Base.printstyled(stderr, "Can't debug while debugging.\n", color=Base.error_color())
  else
    if inREPL[]
      JunoDebugger.enter(mod, ex; initial_continue = initial_continue)
    else
      Base.printstyled(stderr, "Please run the debugger/interpreter in the REPL.\n", color = Base.error_color())
    end
  end
end

isdebugging() = JunoDebugger.isdebugging()


module JunoDebugger

using ..Atom, MacroTools, Lazy, Hiccup

include("breakpoints.jl")
include("repl.jl")
include("stepper.jl")
include("workspace.jl")
include("datatip.jl")

function __init__()
  # @HACK: overwriting these functions enables completions including local bindings while dubugging
  @eval begin
    import REPL.REPLCompletions: get_value, filtered_mod_names
    using REPL.REPLCompletions: appendmacro!, completes_global, ModuleCompletion
    using JuliaInterpreter: locals

    # adapted from https://github.com/JuliaLang/julia/blob/master/stdlib/REPL/src/REPLCompletions.jl#L348
    function get_value(sym::Symbol, fn)
      isdefined(fn, sym) && return getfield(fn, sym), true

      # enables `MethodCompletion`, `PropertyCompletion`, `FieldCompletion` including local bindings
      if isdebugging()
        global STATE
        vars = locals(STATE.frame)
        for var in vars
          sym === var.name && return var.value, true
        end
      end

      return (nothing, false)
    end

    # adapted from https://github.com/JuliaLang/julia/blob/master/stdlib/REPL/src/REPLCompletions.jl#L86-L95
    function filtered_mod_names(ffunc::Function, mod::Module, name::AbstractString, all::Bool = false, imported::Bool = false)
      ssyms = names(mod, all = all, imported = imported)
      filter!(ffunc, ssyms)
      syms = String[string(s) for s in ssyms]

      # inject local names for `ModuleCompletion`s
      if isdebugging()
        global STATE
        @>> locals(STATE.frame) map(v -> string(v.name)) append!(syms)
      end

      macros =  filter(x -> startswith(x, "@" * name), syms)
      appendmacro!(syms, macros, "_str", "\"")
      appendmacro!(syms, macros, "_cmd", "`")
      filter!(x->completes_global(x, name), syms)
      return [ModuleCompletion(mod, sym) for sym in syms]
    end
  end
end

end # module
