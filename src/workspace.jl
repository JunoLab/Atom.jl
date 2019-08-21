handle("workspace") do mod
  mod = getmodule′(mod)
  ns = Symbol.(CodeTools.filtervalid(names(mod; all = true)))
  filter!(ns) do n
    !Base.isdeprecated(mod, n) && isdefined(mod, n) && n != Symbol(mod)
  end
  contexts = [d(:context => string(mod), :items => map(n -> wsitem(mod, n), ns))]
  isdebugging() && prepend!(contexts, JunoDebugger.contexts())
  contexts
end

wsitem(mod, name) = begin
  val = getfield(mod, name)
  wsitem(mod, name, val)
end
wsitem(mod, name, val) = begin
  d(:name       => name,
    :value      => render′(Inline(), val),
    :nativetype => DocSeeker.determinetype(mod, name),
    :type       => wstype(mod, name, val),
    :icon       => wsicon(mod, name, val))
end

#=
@NOTE: `wstype` and `wsicon` are also used for completions / docs
=#

wstype(mod, name, val) = isconst(mod, name) ? "constant" : "variable"
wstype(mod, name, val::Function) = ismacro(val) ? "snippet" : "function"
wstype(mod, name, ::Type) = "type"
wstype(mod, name, ::Module) = "module"
wstype(mod, name, ::Expr) = "mixin"
wstyep(mod, name, ::Symbol) = "tag"
wstype(mod, name, ::Exception) = "mixin"

wsicon(mod, name, val) = isconst(mod, name) ? "c" : "v"
wsicon(mod, name, val::Function) = ismacro(val) ? "icon-mention" : "λ"
wsicon(mod, name, ::Type) = "T"
wsicon(mod, name, ::Module) = "icon-package"
wsicon(mod, name, ::Number) = "n"
wsicon(mod, name, ::AbstractVector) = "icon-list-ordered"
wsicon(mod, name, ::AbstractArray) = "icon-file-binary"
wsicon(mod, name, ::AbstractDict) = "icon-list-unordered"
wsicon(mod, name, ::AbstractString) = "icon-quote"
wsicon(mod, name, ::Regex) = "icon-quote"
wsicon(mod, name, ::Expr) = "icon-code"
wsicon(mod, name, ::Symbol) = "icon-code"
wsicon(mod, name, ::Exception) = "icon-bug"

ismacro(f::Function) = startswith(string(methods(f).mt.name), "@")
