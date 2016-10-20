module Profiler

using Lazy, Juno
import Juno: Row, LazyTree, link, icon
import ..Atom: baselink, cliptrace

include("tree.jl")

function traces()
  traces, stacks = Profile.flatten(Profile.retrieve()...)
  @>>(split(traces, 0, keep = false),
      map(trace -> @>> trace map(x->stacks[x]) cliptrace reverse),
      map(trace -> filter(x->!x.from_c, trace)),
      filter(x->!isempty(x)))
end

const NULLFRAME = StackFrame(symbol(""), symbol(""), -1)

immutable ProfileFrame
  frame::StackFrame
  count::Int
end

ProfileFrame(frame::StackFrame) = ProfileFrame(frame, 1)

typealias ProfileTree Tree{ProfileFrame}

tobranch(trace::StackTrace) = Tree(ProfileFrame(NULLFRAME), [branch(ProfileFrame.(trace))])

mergetrace!(a, b) = merge!(a, b,
                           (==) = (a, b) -> a.frame == b.frame,
                           merge = (a, b) -> ProfileFrame(a.frame, a.count + b.count))

rawtree()::ProfileTree = reduce(mergetrace!, tobranch.(traces()))

function cleantree(tree::ProfileTree)
  postwalk(tree) do x
    length(x.children) == 1 ? first(x.children) : x
  end
end

tree() = cleantree(rawtree())

head(s::StackFrame) =
  Row(Text("$(s.func) at "), baselink(string(s.file), s.line))

@render Juno.Inline prof::Tree{ProfileFrame} begin
  LazyTree(prof.head.frame == NULLFRAME ?
             icon("history") :
             Row(prof.head.count, text" ", head(prof.head.frame)),
           ()->prof.children)
end

end
