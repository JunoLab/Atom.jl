mutable struct Tree{T}
  head::T
  children::Vector{Tree{T}}
  Tree{T}(x::T, children = Tree{T}[]) where T =
    new{T}(x, children)
end

Tree(x, children = []) = Tree{typeof(x)}(x, children)

branch(xs) = length(xs) == 1 ? Tree(xs[1]) : Tree(xs[1], [branch(view(xs,2:lastindex(xs)))])

function mergechild!(children, child; (==) = Base.:(==), kws...)
  for x in children
    if x.head == child.head
      merge!(x, child; (==) = (==), kws...)
      return
    end
  end
  push!(children, child)
  return
end

function Base.merge!(a::Tree, b::Tree; merge = (a, b) -> a, kws...)
  a.head = merge(a.head, b.head)
  for child in b.children
    mergechild!(a.children, child; merge = merge, kws...)
  end
  return a
end

walk(x, inner, outer) = outer(Tree(x.head, map(inner, x.children)))
postwalk(f, x) = walk(x, x -> postwalk(f, x), f)
prewalk(f, x)  = walk(f(x), x -> prewalk(f, x), identity)
