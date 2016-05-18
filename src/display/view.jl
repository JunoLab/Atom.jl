using Hiccup

typealias AString AbstractString

type Model
  data
end

render(::Inline, m::Model) = m.data

view(x::AString) = x
view(x::Associative) = x

view(x) =
  d(:type    => :html,
    :content => stringmime(MIME"text/html"(), x))

view(n::Node) =
  d(:type     => :dom,
    :tag      => tag(n),
    :attrs    => n.attrs,
    :contents => map(view, n.children))

render(::Inline, n::Node) = view(n)

render(::Inline, x::HTML) = view(x)

render(::Inline, x::AbstractFloat) =
  d(:type => :number, :value => float64(x), :full => string(x))

immutable Tree
  head
  children::Vector{Any}
end

render(i::Inline, t::Tree) =
  isempty(t.children) ?
    render(i, t.head) :
    d(:type     => :tree,
      :head     => render(i, t.head),
      :children => map(x->render(i, x),
                       t.children))

immutable SubTree
  label
  child
end

render(i::Inline, t::SubTree) =
  d(:type  => :subtree,
    :label => render(i, t.label),
    :child => render(i, t.child))

type Copyable
  view
  text::String
  Copyable(view, text::AString) = new(view, text)
end

Copyable(view, text) = Copyable(view, render(Clipboard(), text))
Copyable(view) = Copyable(view, view)

render(i::Inline, x::Copyable) =
  d(:type => :copy,
    :view => render(i, x.view),
    :text => x.text)

immutable Link
  file::String
  line::Int
  contents::Vector{Any}
  Link(file::AString, line::Integer, contents...) =
    new(file, line, c(contents...))
end

Link(file::AString, contents...) = Link(file, 0, contents...)

render(i::Inline, l::Link) =
  d(:type => :link,
    :file => l.file,
    :line => l.line-1,
    :contents => map(x->render(i, x), l.contents))

render(::Clipboard, l::Link) =
  "$(l.file):$(l.line)"

link(a...) = Link(a...)
