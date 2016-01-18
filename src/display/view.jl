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
  label
  child
end

render(i::Inline, t::SubTree; options = d()) =
  d(:type  => :subtree,
    :label => render(i, t.label, options = options),
    :child => render(i, t.child, options = options))

# link(x, file) = a(@d("data-file"=>file), x == nothing ? basename(file) : x)
#
# link(x, file, line::Integer) = link(x, "$file:$line")
#
# link(file, line::Integer...) = link(nothing, file, line...)
