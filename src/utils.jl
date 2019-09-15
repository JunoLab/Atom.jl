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

using Pkg, OrderedCollections
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
        try
          for (pkg, infos) in Pkg.Types.read_manifest(manifest)
              if isdefined(infos, :path)
                if infos.path ≠ nothing
                  devpkgs[infos.name] = infos.path
                end
              else
                haskey(first(infos), "path") && (devpkgs[pkg] = first(infos)["path"])
              end
          end
        catch err
          @debug("Error reading manifest.", exception=err)
        end
    end

    sort(devpkgs)
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

function strlimit(str::AbstractString, limit::Int = 30, ellipsis::AbstractString = "…")
  io = IOBuffer()
  for (i, c) in enumerate(str)
    i > limit - length(ellipsis) && break
    isvalid(c) || continue
    print(io, c)
  end
  length(str) >= limit && print(io, ellipsis)
  return String(take!(io))
end

# singleton type for undefined values
struct Undefined end

# get utilities
using CodeTools

"""
    getfield′(mod::Module, name::String, default = Undefined())
    getfield′(mod::Module, name::Symbol, default = Undefined())
    getfield′(object, name::Symbol, default = Undefined())

Returns the specified field of a given `Module` or some arbitrary `object`,
or `default` if no such a field is found.
"""
getfield′(mod::Module, name::String, default = Undefined()) = CodeTools.getthing(mod, name, default)
getfield′(mod::Module, name::Symbol, default = Undefined()) = getfield′(mod, string(name), default)
getfield′(@nospecialize(object), name::Symbol, default = Undefined()) = isdefined(object, name) ? getfield(object, name) : default

"""
    getmodule(mod::String)
    getmodule(parent::Union{Nothing, Module}, mod::String)
    getmodule(code::AbstractString, pos; filemod)

Calls `CodeTools.getmodule(args...)`, but returns `Main` instead of `nothing` in a fallback case.
"""
getmodule(args...) = (m = CodeTools.getmodule(args...)) === nothing ? Main : m

getmethods(mod::String, word::String) = methods(CodeTools.getthing(getmodule(mod), word))

getdocs(mod::Module, word::String) = begin
  md = if Symbol(word) in keys(Docs.keywords)
    Core.eval(Main, :(@doc($(Symbol(word)))))
  else
    include_string(mod, "@doc $word")
  end
  md_hlines(md)
end
getdocs(mod::String, word::String) = getdocs(getmodule(mod), word)
