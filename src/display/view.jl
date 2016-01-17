using Hiccup

typealias AString AbstractString

view(x::AString) = x

view(x) =
  d(:type    => :html,
    :content => stringmime(MIME"text/html"(), x))

view(n::Node) =
  d(:type     => :dom,
    :tag      => tag(n),
    :attrs    => n.attrs,
    :contents => map(view, n.children))

render(::Inline, n::Node; options = d()) = view(n)

render(::Inline, x::HTML; options = d()) = view(x)

type Tree
  head
  children::Vector{Any}
end

render(i::Inline, t::Tree; options = d()) =
  d(:type     => :tree,
    :head     => render(i, t.head, options = options),
    :children => map(x->render(i, x, options = options),
                     t.children))

type SubTree
  head
  child
end

# function render(i::Inline, t::SubTree; options = @d())
#   r(x) = render(i, x, options = options)
#   sub = r(t.child)
#   istree(sub) ? c(r(t.head)*sub[1], sub[2]) : r(span(".gutted", HTML(r(t.head)*sub)))
# end

# link(x, file) = a(@d("data-file"=>file), x == nothing ? basename(file) : x)
#
# link(x, file, line::Integer) = link(x, "$file:$line")
#
# link(file, line::Integer...) = link(nothing, file, line...)
