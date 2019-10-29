import Base: MethodList

stripparams(t) = replace(t, r"\{([A-Za-z, ]*?)\}" => "")

interpose(xs, y) = map(i -> iseven(i) ? xs[i÷2] : y, 2:2length(xs))

const methodloc_regex = r"(?<sig>.+) in (?<mod>.+) at (?<loc>.+)$"

function view(m::Method)
  str = sprint(show, "text/html", m)
  str = replace(str, methodloc_regex => s"\g<sig>")
  str = string("<span>", str, "</span>")
  tv, decls, file, line = Base.arg_decl_parts(m)
  HTML(str), file == :null ? "not found" : Atom.baselink(string(file), line)
end

@render i::Inline m::Method begin
  sig, link = view(m)
  r(x) = render(i, x)
  span(c(r(sig), " at ", r(link)))
end

# TODO: factor out table view
@render i::Inline m::MethodList begin
  ms = collect(m)
  isempty(ms) && return "$(m.mt.name) has no methods."
  r(x) = render(i, x)
  length(ms) == 1 && return r(ms[1])
  Tree(span(c(span(".syntax--support.syntax--function", string(m.mt.name)),
              " has $(length(ms)) methods:")),
       [table(".syntax--methods", [tr(td(c(r(a))), td(c(r(b)))) for (a, b) in map(view, ms)])])
end
