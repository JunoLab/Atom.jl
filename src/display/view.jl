render(::Inline, m::Model) = m.data

view(x::AbstractString) = x
view(x::AbstractDict) = x

view(n::Node) =
  d(:type     => :dom,
    :tag      => tag(n),
    :attrs    => n.attrs,
    :contents => map(view, n.children))

view(n::Node{:code}) =
  d(:type  => :code,
    :attrs => n.attrs,
    :text  => join(n.children, '\n'))

view(n::Hiccup.Node{:latex}) =
  Dict(:type  => :latex,
       :attrs => n.attrs,
       :text  => join(n.children, ' '))

render(::Inline, n::Node) = view(n)

render(::Inline, x::HTML) = view(x)

render(::Console, x::Node) =
  @msg result(view(x))

render(::Editor, x::Node) = view(x)

render(i::Inline, t::Tree) =
  isempty(t.children) ?
    render(i, t.head) :
    d(:type     => :tree,
      :head     => render(i, t.head),
      :children => map(x->render(i, x),
                       t.children))

render(i::Inline, t::SubTree) =
  d(:type  => :subtree,
    :label => render(i, t.label),
    :child => render(i, t.child))

@render i::Inline t::Table begin
  xs = map(x -> render(i, x), t.xs)
  table("", vec(mapslices(xs -> tr("", map(x->td("", [x]), xs)), xs, 2)))
end

render(i::Inline, x::Copyable) =
  d(:type => :copy,
    :view => render(i, x.view),
    :text => x.text)

render(i::Inline, l::Link) =
  d(:type => :link,
    :file => l.file,
    :line => l.line-1,
    :contents => map(x->render(i, x), l.contents))

render(::Clipboard, l::Link) =
  "$(l.file):$(l.line)"
