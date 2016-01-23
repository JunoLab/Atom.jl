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

appendline(path, line) = line > 0 ? "$path:$line" : path

baselink(path, line) =
  path == "no file" ? span(".fade", path) :
  isabspath(path) || isuntitled(path) ?
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
