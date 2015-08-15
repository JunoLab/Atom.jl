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

@render Inline f::Function Text(name(f))

@render i::Inline xs::Vector begin
  Tree(span(strong("Vector"),
            fade(" $(eltype(xs)), $(length(xs))")),
       [render(i, x, options = options) for x in xs])
end
