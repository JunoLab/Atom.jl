function structure(x)
  fields = fieldnames(typeof(x))
  if isempty(fields)
    isbits(x) ?
      Row(typeof(x), Text(" "), x) :
      Row(typeof(x), Text("()"))
  else
    LazyTree(typeof(x), () -> [SubTree(Text("$f → "), structure(getfield′(x, f))) for f in fields])
  end
end

structure(xs::Vector) =
  Tree(Row(eltype(xs), fade("[$(length(xs))]")),
       [isassigned(xs, i) ? structure(xs[i]) : UNDEF for i = 1:length(xs)])

structure(s::Symbol) = s
structure(s::Ptr) = s
structure(s::String) = s
# TODO: do this recursively
structure(x::Array) = x
