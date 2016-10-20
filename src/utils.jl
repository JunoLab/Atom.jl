edit(pkg) =
  isdir(Pkg.dir(pkg)) ?
    run(`atom $(Pkg.dir(pkg))`) :
    error("$pkg not installed")

isuntitled(p) = ismatch(r"^(\.\\|\./)?untitled-[\d\w]+(:\d+)?$", p)

jlhome() = ccall(:jl_get_julia_home, Any, ())

function basepath(file)
  srcdir = joinpath(jlhome(),"..","..","base")
  releasedir = joinpath(jlhome(),"..","share","julia","base")
  normpath(joinpath(isdir(srcdir) ? srcdir : releasedir, file))
end

realpath′(p) = ispath(p) ? realpath(p) : p

fullpath(path) =
  (isuntitled(path) || isabspath(path) ? path : basepath(path)) |> realpath′

appendline(path, line) = line > 0 ? "$path:$line" : path

baselink(path, line) =
  path == "./<missing>" ? span(".fade", "<unknown file>") :
    isuntitled(path) ? link(path, line, Text(appendline("untitled", line))) :
    isabspath(path)  ?
      link(path, line, Text(pkgpath(appendline(path, line)))) :
      link(basepath(path), line, Text(appendline(normpath(joinpath("base", path)), line)))

function pkgpath(path)
  m = match(r"([^/\\]+[/\\]src[/\\].*)$", path)
  m == nothing ? basename(path) : m.captures[1]
end
