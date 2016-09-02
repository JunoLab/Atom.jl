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

# LazyTree(Text("foo"),
#          () -> [Text("bar")])
