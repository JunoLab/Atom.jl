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
  will_append = length(str) > limit

  io = IOBuffer()
  i = 1
  for c in str
    will_append && i > limit - length(ellipsis) && break
    isvalid(c) || continue

    print(io, c)
    i += 1
  end
  will_append && print(io, ellipsis)

  return String(take!(io))
end

shortstr(val) = strlimit(string(val), 20)

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

getmethods(mod::Module, word::String) = methods(CodeTools.getthing(mod, word))
getmethods(mod::String, word::String) = getmethods(getmodule(mod), word)

getdocs(mod::Module, word::String) = begin
  md = if Symbol(word) in keys(Docs.keywords)
    Core.eval(Main, :(@doc($(Symbol(word)))))
  else
    include_string(mod, "@doc $word")
  end
  md_hlines(md)
end
getdocs(mod::String, word::String) = getdocs(getmodule(mod), word)

cangetdocs(mod::Module, word::Symbol) =
  Base.isbindingresolved(mod, word) &&
  !Base.isdeprecated(mod, word) &&
  isdefined(mod, Symbol("@doc"))
cangetdocs(mod::Module, word::String) = cangetdocs(mod, Symbol(word))

#=
module file detections

adapted from https://github.com/timholy/Revise.jl/tree/b0c5c864ea78b93caaa820cb9cfc45eca47f43ff
=#

using Base: PkgId, UUID

"""
    parentfile, included_files = modulefiles(mod::Module)

Return the `parentfile` in which `mod` was defined, as well as a list of any
other files that were `include`d to define `mod`. If this operation is unsuccessful,
`(nothing, nothing)` is returned.
All files are returned as absolute paths.
"""
function modulefiles(mod::Module)
  # NOTE: src_file_key stuff was removed when adapted
  parentfile = String(first(methods(getfield(mod, :eval))).file)
  id = Base.PkgId(mod)
  if id.name == "Base" || Symbol(id.name) ∈ stdlib_names
    parentfile = normpath(Base.find_source_file(parentfile))
    filedata = Base._included_files
  else
    use_compiled_modules() || return nothing, nothing   # FIXME: support non-precompiled packages
    _, filedata = pkg_fileinfo(id)
  end
  filedata === nothing && return nothing, nothing
  included_files = filter(mf -> mf[1] == mod, filedata)
  return fixpath(parentfile), [fixpath(mf[2]) for mf in included_files]
end

function parentfile(mod::Module) # NOTE: added when adapted
  parentfile = String(first(methods(getfield(mod, :eval))).file)
  id = Base.PkgId(mod)
  if id.name == "Base" || id.name == "Core" || Symbol(id.name) ∈ stdlib_names  # NOTE: "Core" is added when adapted
    parentfile = normpath(Base.find_source_file(parentfile))
  end
  fixpath(parentfile)
end

# Fix paths to files that define Julia (base and stdlibs)
function fixpath(
  filename::AbstractString;
  badpath = basebuilddir,
  goodpath = juliadir,
)
  startswith(filename, badpath) || return fullpath(normpath(filename)) # NOTE: `fullpath` added when adapted
  filec = filename
  relfilename = relpath(filename, badpath)
  relfilename0 = relfilename
  for strippath in (joinpath("usr", "share", "julia"),)
    if startswith(relfilename, strippath)
      relfilename = relpath(relfilename, strippath)
      if occursin("stdlib", relfilename0) && !occursin("stdlib", relfilename)
        relfilename = joinpath("stdlib", relfilename)
      end
    end
  end
  ffilename = normpath(joinpath(goodpath, relfilename))
  if (isfile(filename) & !isfile(ffilename))
    ffilename = normpath(filename)
  end
  fullpath(ffilename) # NOTE: `fullpath` added when adapted
end

"""
    basebuilddir

Julia's top-level directory when Julia was built, as recorded by the entries in
`Base._included_files`.
"""
const basebuilddir = let # NOTE: changed from `begin` to `let` when adapted
  sysimg = filter(x -> endswith(x[2], "sysimg.jl"), Base._included_files)[1][2]
  dirname(dirname(sysimg))
end

"""
    juliadir

Constant specifying full path to julia top-level source directory.
This should be reliable even for local builds, cross-builds, and binary installs.
"""
const juliadir = begin
  local jldir = basebuilddir
  if !isdir(joinpath(jldir, "base"))
        # Binaries probably end up here. We fall back on Sys.BINDIR
    jldir = joinpath(Sys.BINDIR, Base.DATAROOTDIR, "julia")
    if !isdir(joinpath(jldir, "base"))
      while true
        trydir = joinpath(jldir, "base")
        isdir(trydir) && break
        trydir = joinpath(jldir, "share", "julia", "base")
        if isdir(trydir)
          jldir = joinpath(jldir, "share", "julia")
          break
        end
        jldirnext = dirname(jldir)
        jldirnext == jldir && break
        jldir = jldirnext
      end
    end
  end
  normpath(jldir)
end

use_compiled_modules() = Base.JLOptions().use_compiled_modules != 0

# For tracking Julia's own stdlibs
const stdlib_names = Set([
  :Base64,
  :CRC32c,
  :Dates,
  :DelimitedFiles,
  :Distributed,
  :FileWatching,
  :Future,
  :InteractiveUtils,
  :Libdl,
  :LibGit2,
  :LinearAlgebra,
  :Logging,
  :Markdown,
  :Mmap,
  :OldPkg,
  :Pkg,
  :Printf,
  :Profile,
  :Random,
  :REPL,
  :Serialization,
  :SHA,
  :SharedArrays,
  :Sockets,
  :SparseArrays,
  :Statistics,
  :SuiteSparse,
  :Test,
  :Unicode,
  :UUIDs,
])

function pkg_fileinfo(id::PkgId)
  uuid, name = id.uuid, id.name
    # Try to find the matching cache file
  paths = Base.find_all_in_cache_path(id)
  sourcepath = Base.locate_package(id)
  for path in paths
    Base.stale_cachefile(sourcepath, path) === true && continue
    provides, includes_requires = parse_cache_header(path)
    mods_files_mtimes, _ = includes_requires
    for (pkgid, buildid) in provides
      if pkgid.uuid === uuid && pkgid.name == name
        return path, mods_files_mtimes
      end
    end
  end
  return nothing, nothing
end

# A near-copy of the same method in `base/loading.jl`. However, this retains the full module path to the file.
function parse_cache_header(f::IO)
  modules = Vector{Pair{PkgId,UInt64}}()
  while true
    n = read(f, Int32)
    n == 0 && break
    sym = String(read(f, n)) # module name
    uuid = UUID((read(f, UInt64), read(f, UInt64))) # pkg UUID
    build_id = read(f, UInt64) # build UUID (mostly just a timestamp)
    push!(modules, PkgId(uuid, sym) => build_id)
  end
  totbytes = read(f, Int64) # total bytes for file dependencies
    # read the list of requirements
    # and split the list into include and requires statements
  includes = Tuple{Module,String,Float64}[]
  requires = Pair{Module,PkgId}[]
  while true
    n2 = read(f, Int32)
    n2 == 0 && break
    depname = String(read(f, n2))
    mtime = read(f, Float64)
    n1 = read(f, Int32)
    mod = (n1 == 0) ? Main : Base.root_module(modules[n1].first)
    if n1 != 0
            # determine the complete module path
      while true
        n1 = read(f, Int32)
        totbytes -= 4
        n1 == 0 && break
        submodname = String(read(f, n1))
        mod = getfield(mod, Symbol(submodname))
        totbytes -= n1
      end
    end
    if depname[1] != '\0'
      push!(includes, (mod, depname, mtime))
    end
    totbytes -= 4 + 4 + n2 + 8
  end
  @assert totbytes == 12 "header of cache file appears to be corrupt"
  return modules, (includes, requires)
end

function parse_cache_header(cachefile::String)
  io = open(cachefile, "r")
  try
    !Base.isvalid_cache_header(io) && throw(ArgumentError("Invalid header in cache file $cachefile."))
    return parse_cache_header(io)
  finally
    close(io)
  end
end
