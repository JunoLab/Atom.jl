using Hiccup

fade(x) = span(".fade", x)

@render Inline x begin
  if isbits(x)
    span(c(fade(string(typeof(x))), " ", string(x)))
  else
    Text(stringmime("text/plain", x))
  end
end

@render Inline x::String Text(sprint(show, x))

@render Inline x::Text begin
  ls = split(string(x), "\n")
  length(ls)>1 ?
    Tree(ls[1], [join(ls[2:end], "\n")]) :
    HTML(ls[1])
end

@render Inline x::Type strong(string(x))

@render Inline x::Module strong(string(x))

name(f::Function) =
  isgeneric(f) ? string(f.env.name) :
  isdefined(f, :env) && isa(f.env,Symbol) ? string(f.env) :
  "λ"

import Base.Docs: doc

@render i::Inline f::Function begin
  if isgeneric(f)
    Tree(name(f), [(doc(f) != nothing ? [render(i, doc(f), options = options)] : [])...
                   render(i, methods(f), options = options)])
  else
    Text(name(f))
  end
end

@render i::Inline xs::Vector begin
  Tree(span(strong("Vector"),
            fade(" $(eltype(xs)), $(length(xs))")),
       [render(i, x, options = options) for x in xs])
end

@render i::Inline d::Dict begin
  head = span(c(strong("Dict"),
              fade(" $(eltype(d).parameters[1]) → $(eltype(d).parameters[2])")))
  children = c()
  for (k, v) in d
    key = render(i, k, options = options)
    child = render(i, v, options = options)
    if isa(child, Tree)
      push!(children, Tree(span(c(key, " → ", child.head)),
                           child.children))
    else
      push!(children, span(".gutted", c(key, " → ", child)))
    end
  end
  Tree(head, children)
end

@render i::Inline x::Number Text(sprint(show, x))
