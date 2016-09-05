# TODO: only store last N trees

import Juno: LazyTree

_id = 0

treeid() = (global _id += 1)

const trees = Dict{Int,LazyTree}()

function render(i::Inline, tree::LazyTree)
  id = treeid()
  trees[id] = tree
  d(:type => :lazy,
    :head => render(i, tree.head),
    :id => id)
end

handle("getlazy") do id
  haskey(trees, id) || return [render(Inline(), fade("[out of date result]"))]
  return [render(Inline(), x) for x in pop!(trees, id).children()]
end

handle("clearLazy") do id
  delete!(trees, id)
end
