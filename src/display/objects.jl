using Hiccup

fade(x) = span(".fade", x)

@render Inline x begin
  if isbits(x)
    span(c(fade(string(typeof(x))), " ", string(x)))
  else
    Text(stringmime("text/plain", x))
  end
end

@render Inline x::AbstractString Text(sprint(show, x))

@render Inline x::Text begin
  ls = split(string(x), "\n")
  length(ls)>1 ?
    Tree(Text(ls[1]), [HTML(join(ls[2:end], "\n"))]) :
    HTML(ls[1])
end

@render Inline x::Type strong(string(x))

@render Inline x::Module strong(string(x))

name(f::Function) =
  isgeneric(f) ? string(f.env.name) :
  isdefined(f, :env) && isa(f.env,Symbol) ? string(f.env) :
  "λ"

import Base.Docs: doc

@render Inline f::Function begin
  if isgeneric(f)
    Tree(Text(name(f)), [(doc(f) != nothing ? [doc(f)] : [])..., methods(f)])
  else
    Text(name(f))
  end
end

@render Inline xs::Vector begin
  length(xs) <= 25 ? children = xs :
                     children = [xs[1:10]; "..."; xs[end-9:end]]
    Tree(span(strong("Vector"),
              fade(" $(eltype(xs)), $(length(xs))")),
         children)
end

@render i::Inline d::Dict begin
  j = 0
  st = Array{Atom.SubTree}(0)
  for (key, val) in d
    push!(st, SubTree(span(c(render(i, key, options = options), " → ")), val))
    j += 1
    j > 25 && (push!(st, SubTree(span("... → "), span("..."))); break)
  end
  Tree(span(c(strong("Dict"),
            fade(" $(eltype(d).parameters[1]) → $(eltype(d).parameters[2]) with $(length(d)) entries"))), st)
end

@render i::Inline x::Number Text(sprint(show, x))
