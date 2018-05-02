edit(pkg) =
  isdir(Pkg.dir(pkg)) ?
    run(`atom $(Pkg.dir(pkg))`) :
    error("$pkg not installed")

isuntitled(p) = ismatch(r"^(\.\\|\./)?untitled-[\d\w]+(:\d+)?$", p)

jlhome() = ccall(:jl_get_julia_home, Any, ())

appendline(path, line) = line > 0 ? "$path:$line" : path

function realpath′(p)
  try
    ispath(p) ? realpath(p) : p
  catch e
    p
  end
end

function basepath(file)
  srcdir = joinpath(jlhome(),"..","..","base")
  releasedir = joinpath(jlhome(),"..","share","julia","base")
  normpath(joinpath(isdir(srcdir) ? srcdir : releasedir, file))
end

fullpath(path) =
  (isuntitled(path) || isabspath(path) ? path : basepath(path)) |> realpath′

function pkgpath(path)
  m = match(r"([^/\\]+[/\\]src[/\\].*)$", path)
  m == nothing ? basename(path) : m.captures[1]
end

expandpath(path) =
  isempty(path) ? (path, path) :
  path == "./missing" ? ("<unknown file>", path) :
  isuntitled(path) ? ("untitled", path) :
  !isabspath(path) ? (normpath(joinpath("base", path)), basepath(path)) :
  (pkgpath(path), path)

function baselink(path, line)
  name, path = expandpath(path)
  name == "<unkown file>" ? span(".fade", "<unknown file>") :
                            link(path, line, Text(appendline(name, line)))
end
