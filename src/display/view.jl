using Hiccup

typealias AString AbstractString

import Juno: Model

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

render(::Console, x::Node) =
  @msg result(view(x))

render(::Editor, x::Node) = view(x)

render(::Inline, x::AbstractFloat) =
  isnan(x) || isinf(x) ?
    view(span(".constant.number", string(x))) :
    d(:type => :number, :value => Float64(x), :full => string(x))

@render Inline x::Expr begin
  text = string(x)
  length(split(text, "\n")) == 1 ?
    Model(d(:type => :code, :text => text)) :
    Tree(Text("Code"),
         [Model(d(:type => :code, :text => text))])
end

render(::Console, x::Expr) =
  @msg result(d(:type => :code, :text => string(x)))

import Juno: Tree, SubTree

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

import Juno: Copyable

render(i::Inline, x::Copyable) =
  d(:type => :copy,
    :view => render(i, x.view),
    :text => x.text)

import Juno: Link

render(i::Inline, l::Link) =
  d(:type => :link,
    :file => l.file,
    :line => l.line-1,
    :contents => map(x->render(i, x), l.contents))

render(::Clipboard, l::Link) =
  "$(l.file):$(l.line)"

link(a...) = Link(a...)
