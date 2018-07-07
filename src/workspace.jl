ismacro(f::Function) = startswith(string(methods(f).mt.name), "@")

wstype(x) = ""
wstype(::Module) = "module"
wstype(f::Function) = "function"
wstype(::Type) = "type"
wstype(::Expr) = "mixin"
wstype(::Symbol) = "tag"
wstype(::AbstractString) = "property"
wstype(::Number) = "constant"
wstype(::Exception) = "tag"

wsicon(x) = ""
wsicon(f::Function) = ismacro(f) ? "icon-mention" : ""
wsicon(::AbstractArray) = "icon-file-binary"
wsicon(::AbstractVector) = "icon-list-ordered"
wsicon(::AbstractString) = "icon-quote"
wsicon(::Expr) = "icon-code"
wsicon(::Symbol) = "icon-code"
wsicon(::Exception) = "icon-bug"
wsicon(::Number) = "n"

wsnamed(name, val) = false
wsnamed(name, f::Function) = name == methods(f).mt.name
wsnamed(name, m::Module) = name == module_name(m)
wsnamed(name, T::DataType) = name == Symbol(T.name)

function wsitem(name, val)
  d(:name  => name,
    :value => render′(Inline(), val),
    :type  => wstype(val),
    :icon  => wsicon(val))
end

wsitem(mod::Module, name::Symbol) = wsitem(name, getfield(mod, name))

handle("workspace") do mod
  mod = getmodule′(mod)
  ns = filter!(x->!Base.isdeprecated(mod, x), Symbol.(CodeTools.filtervalid(names(mod, all=true))))
  filter!(n -> isdefined(mod, n), ns)
  # TODO: only filter out imported modules
  filter!(n -> !isa(getfield(mod, n), Module), ns)
  contexts = [d(:context => string(mod), :items => map(n -> wsitem(mod, n), ns))]
  if isdebugging()
    prepend!(contexts, Debugger.contexts())
  end
  return contexts
end
