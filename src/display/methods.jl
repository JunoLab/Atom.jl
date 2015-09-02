using Hiccup, Lazy

const abspathpattern =
  @windows? r"([a-zA-Z]+:[\\/][a-zA-Z_\./\\ 0-9]+\.jl)(?::([0-9]*))?" : r"(/[a-zA-Z_\./ 0-9]+\.jl)(?::([0-9]*))?"

# Make the prefix optional, but disallow spaces
const relpathpattern =
  @windows? r"([a-zA-Z_\./\\0-9]+\.jl)(?::([0-9]*))?$" : r"([a-zA-Z_\./0-9]+\.jl)(?::([0-9]*))?$"

basepath(file) = joinpath(JULIA_HOME,"..","share","julia","base",file) |> normpath

baselink(path) =
  ismatch(relpathpattern, path) ?
    link(path, basepath(path)) :
    link(path)

stripparams(t) = replace(t, r"\{([A-Za-z, ]*?)\}", "")

function methodarray(mt::MethodTable)
  defs = Method[]
  d = mt.defs
  while !is(d,nothing)
    push!(defs, d)
    d = d.next
  end
  file(m) = m.func.code.file |> string |> basename
  line(m) = m.func.code.line
  sort!(defs, lt = (a, b) -> file(a) == file(b) ?
                               line(a) < line(b) :
                               file(a) < file(b))
  return defs
end

methodarray(x) = methodarray(methods(x))

function view(m::Method)
  tv, decls, file, line = Base.arg_decl_parts(m)
  params = [span(c(x, isempty(T) ? "" : "::", strong(stripparams(T)))) for (x, T) in decls]
  params = interpose(params, ", ")
  span(c(string(m.func.code.name),
         "(", params..., ")")),
  baselink("$file:$line")
end

@render i::Inline m::MethodTable begin
  ms = methodarray(m)
  isempty(m) && return "$(m.name) has no methods."
  Tree("$(m.name) has $(length(ms)) method$(length(ms)==1?"":"s"):",
       [table(".methods", [tr(td(a), td(b)) for (a, b) in map(view, ms)])])
end
