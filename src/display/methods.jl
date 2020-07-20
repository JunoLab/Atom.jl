import Base: MethodList

stripparams(t) = replace(t, r"\{([A-Za-z, ]*?)\}" => "")

interpose(xs, y) = map(i -> iseven(i) ? xs[i÷2] : y, 2:2length(xs))

const methodloc_regex = r"(?<sig>.+) in (?<mod>.+) at (?<loc>.+)$"
const anon_sig_head_regex = reg = r"^\(.*::.*var\".*?\)"

function view(m::Method)
  str = sprint(show, "text/html", m)
  str = replace(str, methodloc_regex => s"\g<sig>")
  str = replace(str, anon_sig_head_regex => "λ")
  str = string("<span>", str, "</span>")
  tv, decls, file, line = Base.arg_decl_parts(m)
  HTML(str), file == :null ? "not found" : Atom.baselink(string(file), line)
end

@render i::Inline m::Method begin
  sig, link = view(m)
  r(x) = render(i, x)
  span(c(r(sig), " at ", r(link)))
end

function methods_table(i, methods)
  r(x) = render(i, x)
  table(".syntax--methods", [tr(td(c(r(a))), td(c(r(b)))) for (a, b) in map(view, methods)])
end

@render i::Inline m::MethodList begin
  ms = collect(m)
  methodname = string(m.mt.name)
  startswith(methodname, "#") && (methodname = "λ")
  isempty(ms) && return "$methodname has no methods."
  length(ms) == 1 && return render(i, ms[1])
  Tree(span(c(span(".syntax--support.syntax--function", methodname),
              " has $(length(ms)) methods:")),
              [methods_table(i, m)])
end
