using Hiccup

fade(x) = span(".fade", x)

function render(d::Inline, x; options = @d())
  if isbits(x)
    render(d, Text("$(typeof(x)): $x"), options = options)
  else
    render(d, Text(stringmime("text/plain", x)), options = options)
  end
end

render(i::Inline, x::String; options = options) =
  render(i, Text(sprint(show, x)), options = options)

function render(i::Inline, x::Text; options = @d())
  ls = split(string(x), "\n")
  render(i, length(ls)>1 ?
              Tree(ls[1], [join(ls[2:end], "\n")]) :
              HTML(ls[1]), options = options)
end

render(i::Inline, x::Type; options = @d()) =
  render(i, strong(string(x)), options = options)

render(i::Inline, x::Module; options = @d()) =
  render(i, strong(string(x)), options = options)

name(f::Function) =
  isgeneric(f) ? string(f.env.name) :
  isdefined(f, :env) && isa(f.env,Symbol) ? string(f.env) :
  "λ"

render(i::Inline, f::Function; options = @d()) =
  render(i, Text(name(f)), options = options)

function render(i::Inline, xs::Vector; options = @d())
  render(i, Tree(span(strong("Vector"),
                      fade(" $(eltype(xs)), $(length(xs))")),
                 [render(i, x, options = options) for x in xs]),
            options = options)
end
