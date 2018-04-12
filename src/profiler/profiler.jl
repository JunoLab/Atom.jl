module Profiler

using JSON
using Lazy, Juno, Hiccup
import Juno: Row, LazyTree, SubTree, icon
import ..Atom: baselink, cliptrace, expandpath, @msg, handle
using Base.StackTraces

include("tree.jl")

function traces()
  traces, stacks = Profile.flatten(Profile.retrieve()...)
  @>>(split(traces, 0, keep = false),
      map(trace -> @>> trace map(x->stacks[x]) cliptrace reverse),
      map(trace -> filter(x->!x.from_c, trace)),
      filter(x->!isempty(x)))
end

const NULLFRAME = StackFrame(Symbol(""), Symbol(""), -1)

immutable ProfileFrame
  frame::StackFrame
  count::Int
end

ProfileFrame(frame::StackFrame) = ProfileFrame(frame, 1)

const ProfileTree = Tree{ProfileFrame}

tobranch(trace::StackTrace) = Tree(ProfileFrame(NULLFRAME), [branch(ProfileFrame.(trace))])

mergetrace!(a, b) = merge!(a, b,
                           (==) = (a, b) -> a.frame == b.frame,
                           merge = (a, b) -> ProfileFrame(a.frame, a.count + b.count))

rawtree()::ProfileTree = reduce(mergetrace!, tobranch.(traces()))

function cleantree(tree::ProfileTree)
  postwalk(tree) do x
    length(x.children) == 1 ? Tree(x.head, x.children[1].children) : x
  end
end

tree() = isempty(Profile.fetch()) ? error("No profile data") : cleantree(rawtree())

head(s::StackFrame) =
  Row(span(".syntax--support.syntax--function", string(s.func)),
      text" at ",
      baselink(string(s.file), s.line))

@render Juno.Inline prof::ProfileTree begin
  h = prof.head.frame == NULLFRAME ?
    icon("history") :
    Row(prof.head.count, text" ", head(prof.head.frame))
  isempty(prof.children) ? SubTree(h, text"") : LazyTree(h, ()->prof.children)
end

function tojson(prof::ProfileTree)
  name, path = expandpath(string(prof.head.frame.file))
  Dict(:path => path,
       :location => name,
       :func => prof.head.frame.func,
       :line => prof.head.frame.line,
       :count => prof.head.count,
       :children => map(tojson, prof.children))
end

profiler() = @msg profile(tojson(tree()))


handle("loadProfileTrace") do path
  if path === nothing
    return
  end

  json = try
    JSON.parse(String(open(read, first(path))))
  catch e
    error("Error reading profile trace file at $path.")
    nothing
  end
  json !== nothing && @msg profile(json)
end

handle("saveProfileTrace") do path, data
  if path === nothing
    return
  end

  try
    write(path, JSON.json(data))
  catch e
    error("Error writing profile trace file at $path.")
  end
end

end
