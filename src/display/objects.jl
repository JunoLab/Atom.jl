using Hiccup

fade(x) = span(".fade", x)

@render Inline x::Text begin
  ls = split(string(x), "\n")
  length(ls) > 1 ?
    Tree(Model(ls[1]), c(Model(join(ls[2:end], "\n")))) :
    span(ls[1])
end

@render Inline x begin
  if isbits(x)
    span(c(fade(string(typeof(x))), " ", string(x)))
  else
    Text(stringmime("text/plain", x))
  end
end

@render Inline x::Type span(".support.type", string(x))

@render Inline x::Module span(".keyword.other", string(x))

import Base.Docs: doc

isanon(f) = contains(string(f), "#")

@render Inline f::Function begin
  isanon(f) ? span(".support.function", "λ") :
    Tree(span(".support.function", string(typeof(f).name.mt.name)),
         [(CodeTools.hasdoc(f) ? [doc(f)] : [])..., methods(f)])
end

@render i::Inline xs::Vector begin
  length(xs) <= 25 ? children = handleundefs(xs) :
                     children = [handleundefs(xs, 1:10); span("..."); handleundefs(xs, length(xs)-9:length(xs))]
    Tree(span(c(render(i, eltype(xs)), fade("[$(length(xs))]"))),
         children)
end

@render i::Inline d::Dict begin
  j = 0
  st = Array{Atom.SubTree}(0)
  for (key, val) in d
    push!(st, SubTree(span(c(render(i, key), " → ")), val))
    j += 1
    j > 25 && (push!(st, SubTree(span("... → "), span("..."))); break)
  end
  Tree(span(c(strong("Dict"),
            fade(" $(eltype(d).parameters[1]) → $(eltype(d).parameters[2]) with $(length(d)) entries"))), st)
end

@render Inline x::Number span(".constant.number", string(x))

@render i::Inline x::Complex begin
  span(c(render(i, real(x)), " + ", render(i, imag(x)), "im"))
end

@render i::Inline x::AbstractString begin
  span(".string", c(render(i, Text(stringmime("text/plain", x)))))
end

render{sym}(i::Inline, x::Irrational{sym}) =
  render(i, span(c(string(sym), " = ", render(i, float(x)), "...")))

handleundefs(X::Vector) = handleundefs(X, 1:length(X))

function handleundefs(X::Vector, inds)
  Xout = Vector{Union{String, eltype(X)}}(length(inds))
  j = 1
  for i in inds
    Xout[j] = isdefined(X, i) ? X[i] : "#undef"
    j += 1
  end
  Xout
end

@render i::Inline xs::Tuple begin
  span(c("(", (@_ xs map(x->render(i, x), _) interpose(_, ", "))..., ")"))
end
