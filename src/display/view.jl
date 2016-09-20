using Hiccup

typealias AString AbstractString

import Juno: Model, view

render(::Inline, m::Model) = m.data

view(x::AString) = x
view(x::Associative) = x

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

import Juno: Link, link

render(i::Inline, l::Link) =
  d(:type => :link,
    :file => l.file,
    :line => l.line-1,
    :contents => map(x->render(i, x), l.contents))

render(::Clipboard, l::Link) =
  "$(l.file):$(l.line)"

import Juno: icon, fade
