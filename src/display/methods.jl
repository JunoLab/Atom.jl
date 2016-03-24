using Hiccup, Lazy

isuntitled(p) = ismatch(r"^untitled-[\d\w]+(:\d+)?$", p)

realpath′(p) = ispath(p) ? realpath(p) : p

basepath(file) = joinpath(JULIA_HOME,"..","share","julia","base",file)

fullpath(path) =
  (isuntitled(path) || isabspath(path) ? path : basepath(path)) |> realpath′

function pkgpath(path)
  m = match(r"([^/\\]+[/\\]src[/\\].*)$", path)
  m == nothing ? basename(path) : m.captures[1]
end

findpath(path) =
  isabspath(path) || isuntitled(path) ?
    (pkgpath(path), path) :
    (normpath("base/$path"), basepath(path))

appendline(path, line) = line > 0 ? "$path:$line" : path

baselink(path, line) =
  path == "no file" ? span(".fade", path) :
  isuntitled(path) ? link(path, line, Text(appendline("untitled", line))) :
  isabspath(path)  ?
    link(path, line, Text(pkgpath(appendline(path, line)))) :
    link(basepath(path), line, Text(normpath("base/$(appendline(path, line))")))

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
  file == :null ? "not found" : baselink(string(file), line)
end

@render i::Inline m::Method begin
  sig, link = view(m)
  r(x) = render(i, x, options = options)
  span(c(r(sig), " at ", r(link)))
end

# TODO: factor out table view
@render i::Inline m::MethodTable begin
  ms = methodarray(m)
  isempty(m) && return "$(m.name) has no methods."
  r(x) = render(i, x, options = options)
  Tree(Text("$(m.name) has $(length(ms)) method$(length(ms)==1?"":"s"):"),
       [table(".methods", [tr(td(c(r(a))), td(c(r(b)))) for (a, b) in map(view, ms)])])
end

@render i::Inline ms::Vector{Method} begin
  isempty(ms) && return "No methods found."
  Tree(Text("$(length(ms)) method$(length(ms)==1?"":"s") found:"),
       [table(".methods", [tr(td(a), td(b)) for (a, b) in map(view, ms)])])
end

function view_obj(m::Method)
  tv, decls, file, line = Base.arg_decl_parts(m)
  signature = [string(x, isempty(T) ? "" : "::", stripparams(T)) for (x, T) in decls]
  signature = string(m.func.code.name, "(", join(signature, ", "), ")")
  signature, findpath(string(file))..., line
end

method_obj(m::MethodTable) = method_obj(methodarray(m))

function method_obj(ms)
  isempty(ms) && return []
  [@d(
    :text => signature,
    :dispfile => dispfile,
    :file => file,
    :line => line - 1 # Atom starts counting at 0, Julia at 1
  ) for (signature, dispfile, file, line) in map(view_obj, ms)]
end
