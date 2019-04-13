include("path_matching.jl")

isuntitled(p) = occursin(r"^(\.\\|\./)?untitled-[\d\w]+(:\d+)?$", p)

appendline(path, line) = line > 0 ? "$path:$line" : path

function realpath′(p)
  try
    ispath(p) ? realpath(p) : p
  catch e
    p
  end
end

function isfile′(p)
  try
    isfile(p)
  catch
    false
  end
end

using Pkg
function finddevpackages()
    usage_file = joinpath(Pkg.logdir(), "manifest_usage.toml")
    manifests = Set{String}()
    if isfile(usage_file)
        for (manifest_file, infos) in Pkg.TOML.parse(String(read(usage_file)))
            push!(manifests, manifest_file)
        end
    else
        push!(manifests, Pkg.Types.Context().env.manifest_file)
    end
    devpkgs = Dict{String, String}()
    for manifest in manifests
        isfile(manifest) || continue
        for (pkg, infos) in Pkg.Types.read_manifest(manifest)
            haskey(first(infos), "path") && (devpkgs[pkg] = first(infos)["path"])
        end
    end

    devpkgs
end

function basepath(file)
  srcdir = joinpath(Sys.BINDIR,"..","..","base")
  releasedir = joinpath(Sys.BINDIR,"..","share","julia","base")
  normpath(joinpath(isdir(srcdir) ? srcdir : releasedir, file))
end

fullpath(path) =
  (isuntitled(path) || isabspath(path) ? path : basepath(path)) |> realpath′

function pkgpath(path)
  m = match(r"((?:[^/\\]+[/\\]){2}src[/\\].*)$", path)
  m == nothing ? basename(path) : m.captures[1]
end

expandpath(path) =
  isempty(path) ? (path, path) :
    path == "./missing" ? ("<unknown file>", path) :
      isuntitled(path) ? ("untitled", path) :
        !isabspath(path) ? (normpath(joinpath("base", path)), basepath(path)) :
          occursin(joinpath("julia", "stdlib"), path) ?
            begin
              p = last(split(path, joinpath("julia", "stdlib", "")))
              return (normpath(joinpath("stdlib", p)), isfile′(path) ? path :
                                                       normpath(joinpath(basepath(joinpath("..", "stdlib")), p)))
            end :
            (pkgpath(path), path)

function baselink(path, line)
  name, path = expandpath(path)
  name == "<unkown file>" ? span(".fade", "<unknown file>") :
                            link(path, line, Text(appendline(name, line)))
end

using Markdown: MD, HorizontalRule
function md_hlines(md)
  if !isa(md, MD) || !haskey(md.meta, :results) || isempty(md.meta[:results])
      return md
  end
  v = Any[]
  for (n, doc) in enumerate(md.content)
      push!(v, doc)
      n == length(md.content) || push!(v, HorizontalRule())
  end
  return MD(v)
end

function strlimit(str::AbstractString, limit = 30)
  str = lastindex(str) > limit ?  str[1:prevind(str, limit)]*"…" : str
  filter(isvalid, str)
end
