using Hiccup, Lazy

isuntitled(p) = ismatch(r"^untitled-\d+(:\d+)?$", p)

realpath′(p) = ispath(p) ? realpath(p) : p

basepath(file) = joinpath(JULIA_HOME,"..","share","julia","base",file)

fullpath(path) =
  (isuntitled(path) || isabspath(path) ? path : basepath(path)) |> realpath′

function pkgpath(path)
  m = match(r"([^/\\]+[/\\]src[/\\].*)$", path)
  m == nothing ? basename(path) : m.captures[1]
end

baselink(path) =
  isabspath(path) || isuntitled(path) ?
    link(pkgpath(path), path) :
    link(normpath("base/$path"), basepath(path))

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
  file == :null ? "not found" :baselink("$file:$line")
end

@render i::Inline m::MethodTable begin
  ms = methodarray(m)
  isempty(m) && return "$(m.name) has no methods."
  Tree(Text("$(m.name) has $(length(ms)) method$(length(ms)==1?"":"s"):"),
       [table(".methods", [tr(td(a), td(b)) for (a, b) in map(view, ms)])])
end

@render i::Inline ms::Vector{Method} begin
  isempty(ms) && return "No methods found."
  Tree(Text("$(length(ms)) method$(length(ms)==1?"":"s") found:"),
       [table(".methods", [tr(td(a), td(b)) for (a, b) in map(view, ms)])])
end
