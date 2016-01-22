using Hiccup

typealias AString AbstractString

type Model
  data
end

render(::Inline, m::Model; options = d()) = m.data

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

render(::Inline, n::Node; options = d()) = view(n)

render(::Inline, x::HTML; options = d()) = view(x)

immutable Tree
  head
  children::Vector{Any}
end

render(i::Inline, t::Tree; options = d()) =
  d(:type     => :tree,
    :head     => render(i, t.head, options = options),
    :children => map(x->render(i, x, options = options),
                     t.children))

immutable SubTree
  label
  child
end

render(i::Inline, t::SubTree; options = d()) =
  d(:type  => :subtree,
    :label => render(i, t.label, options = options),
    :child => render(i, t.child, options = options))

type Copyable
  view
  text::UTF8String
  Copyable(view, text::AString) = new(view, text)
end

Copyable(view, text) = Copyable(view, render(Clipboard(), text))
Copyable(view) = Copyable(view, view)

render(i::Inline, x::Copyable; options = d()) =
  d(:type => :copy,
    :view => render(i, x.view, options = options),
    :text => x.text)

immutable Link
  file::UTF8String
  line::Int
  contents::Vector{Any}
  Link(file::AString, line::Integer, contents...) =
    new(file, line, c(contents...))
end

Link(file::AString, contents...) = Link(file, -1, contents...)

render(i::Inline, l::Link; options = d()) =
  d(:type => :link,
    :file => l.file,
    :line => l.line-1,
    :contents => map(x->render(i, x, options = options), l.contents))

render(::Clipboard, l::Link; options = d()) =
  "$(l.file):$(l.line)"

link(a...) = Link(a...)
