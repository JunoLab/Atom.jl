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

wstype(mod, name, val) = begin
  val isa Function ? "function" :
    val isa Type ? "type" :
    val isa Module ? "module" :
    val isa Expr ? "mixin" :
    val isa Symbol ? "tag" :
    val isa Exception ? "mixin" :
    isconst(mod, name) ? "constant" : "variable"
end

wsicon(mod, name, val) = begin
  val isa Function ? (ismacro(val) ? "icon-mention" : "λ") :
    val isa Type ? "T" :
    val isa Module ? "icon-package" :
    val isa Number ? "n" :
    val isa AbstractVector ? "icon-list-ordered" :
    val isa AbstractArray ? "icon-file-binary" :
    val isa AbstractString ? "icon-quote" :
    val isa Regex ? "icon-quote" :
    val isa Expr ? "icon-code" :
    val isa Symbol ? "icon-code" :
    val isa Exception ? "icon-bug" :
    isconst(mod, name) ? "c" : "v"
end

ismacro(f::Function) = startswith(string(methods(f).mt.name), "@")
