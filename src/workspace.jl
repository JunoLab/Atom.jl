function workspace(mod)
  mod = getmodule(mod)
  ns = Symbol.(CodeTools.filtervalid(names(mod; all = true)))
  filter!(ns) do n
    !Base.isdeprecated(mod, n) &&
    string(n) != last(split(string(mod), '.'))
  end
  contexts = [d(:context => string(mod), :items => map(n -> wsitem(mod, n), ns))]
  isdebugging() && prepend!(contexts, JunoDebugger.contexts())
  contexts
end

handle(workspace, "workspace")

update_workspace() = @msg updateWorkspace()

wsitem(mod, name) = begin
  val = getfield′(mod, name)
  wsitem(mod, name, val)
end
wsitem(mod, name, @nospecialize(val)) = begin
  d(:name       => name,
    :value      => render′(Inline(), val),
    :nativetype => nativetype(mod, name, val),
    :type       => wstype(mod, name, val),
    :icon       => wsicon(mod, name, val))
end

nativetype(mod, name, @nospecialize(val)) = DocSeeker.determinetype(mod, name)
nativetype(mod, name, ::Undefined) = "Undefined"

#=
@NOTE: `wstype` and `wsicon` are also used for completions / docs
=#

wstype(mod, name, @nospecialize(val)) = isconst(mod, name) ? "constant" : "variable"
wstype(mod, name, f::Function) = ismacro(f) ? "snippet" : "function"
wstype(mod, name, ::Type) = "type"
wstype(mod, name, ::Module) = "module"
wstype(mod, name, ::Expr) = "mixin"
wstype(mod, name, ::Symbol) = "tag"
wstype(mod, name, ::Exception) = "mixin"
wstype(mod, name, ::Undefined) = "ignored"

wsicon(mod, name, @nospecialize(val)) = isconst(mod, name) ? "c" : "v"
wsicon(mod, name, f::Function) = ismacro(f) ? "icon-mention" : "λ"
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
wsicon(mod, name, ::Undefined) = "icon-circle-slash"
