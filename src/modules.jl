#=
finding all the included files for a module

1. Revise-like approach
  * mostly adapted from https://github.com/timholy/Revise.jl/tree/b0c5c864ea78b93caaa820cb9cfc45eca47f43ff
  * only works for precompiled modules
2. CSTPraser-based approach
  * static parsing -- works for all the files but costly
  * TODO: excludes files in submodules when searched from the parent module
  * TODO: looks for non-toplevel `include` calls
=#

# Revise-like approach
# --------------------

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

# Fix paths to files that define Julia (base and stdlibs)
function fixpath(
  filename::AbstractString;
  badpath = basebuilddir,
  goodpath = basepath("..")
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

# CSTParser-based approach
# ------------------------

"""
    included_files = modulefiles(mod::String, entrypath::String)::Vector{String}

Returns all the files in `mod` module that can be reached via [`include`](@ref)
  calls from `entrypath`.
Note this function currently only looks for static toplevel calls (i.e. miss the
  calls in non-toplevel scope).
"""
function modulefiles(mod::String, entrypath::String, files = Vector{String}())
  isfile′(entrypath) || return files

  push!(files, entrypath)

  text = read(entrypath, String)
  items = toplevelitems(text; mod = mod)

  for item in items
    if item isa ToplevelCall
      expr = item.expr
      if isinclude(expr)
        nextfile = expr.args[3].val
        nextentrypath = joinpath(dirname(entrypath), nextfile)
        isfile(nextentrypath) || continue
        modulefiles(mod, nextentrypath, files)
      end
    end
  end

  return files
end


#=
find entry file of a module
=#

"""
    entrypath, line = moduledefinition(mod::Module)

Returns an entry file of `mod`, and its definition line.

!!! note
    This function works for non-precompiled packages.
"""
function moduledefinition(mod::Module) # NOTE: added when adapted
  evalmethod = first(methods(getfield(mod, :eval)))
  parentfile = String(evalmethod.file)
  line = evalmethod.line
  id = Base.PkgId(mod)
  if id.name == "Base" || id.name == "Core" || Symbol(id.name) ∈ stdlib_names  # NOTE: "Core" is added when adapted
    parentfile = normpath(Base.find_source_file(parentfile))
  end
  fixpath(parentfile), line
end


#=
auto-module detection for the current file

# TODO:
# use the same logics as finding module files for this auto-module detection
# ref: https://github.com/JunoLab/Juno.jl/issues/411
=#

using CodeTools, LNR

LNR.cursor(data::AbstractDict) = cursor(data["row"], data["column"])

function modulenames(data, pos)
  main = haskey(data, "module") ? data["module"] :
         haskey(data, "path") ? CodeTools.filemodule(data["path"]) :
         "Main"
  main == "" && (main = "Main")
  sub = CodeTools.codemodule(data["code"], pos)
  main, sub
end

# keeps the latest file that has been used for Main module scope
const MAIN_MODULE_LOCATION = Ref{Tuple{String, Int}}(moduledefinition(Main))

handle("module") do data
  main, sub = modulenames(data, cursor(data))

  mod = CodeTools.getmodule(main)
  smod = CodeTools.getmodule(mod, sub)

  if main == "Main" && sub == ""
    MAIN_MODULE_LOCATION[] = get!(data, "path", ""), data["row"]
  end

  return d(:main => main,
           :sub  => sub,
           :inactive => (mod==nothing),
           :subInactive => smod==nothing)
end


#=
find all modules
=#

handle("allmodules") do
  sort!([string(m) for m in CodeTools.allchildren(Main)])
end
