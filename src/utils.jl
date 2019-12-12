# file utilities
# --------------

function isfile′(p)
  try
    isfile(p)
  catch
    false
  end
end

iswritablefile(file) = Base.uperm(file) == 0x06
nonwritablefiles(files) = filter(!iswritablefile, files)

# path utilities
# --------------

include("path_matching.jl")

"""
    isuntitled(path::AbstractString)

Checks if `path` represents an unsaved editor.
Usualy the string that follows `"untitled-"` is obtained from `editor.getBuffer().getId()`:
  e.g. `path = "untitled-266305858c1298b906bed15ddad81cea"`.
"""
isuntitled(path::AbstractString) = occursin(r"^(\.\\|\./)?untitled-[\d\w]+(:\d+)?$", path)

appendline(path, line) = line > 0 ? "$path:$line" : path

function realpath′(p)
  try
    ispath(p) ? realpath(p) : p
  catch e
    p
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

  devpkgs = OrderedDict{String,String}()
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
      @debug("Error reading manifest.", exception = err)
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

# string utilties
# ---------------

"""
    strlimit(str::AbstractString, limit::Int = 30, ellipsis::AbstractString = "…")

Chops off `str` so that its _length_ doesn't exceed `limit`. The excessive part
  will be replaced by `ellipsis`.

!!! note
    The length of returned string will _never_ exceed `limit`.
"""
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

"""used to strip parent module prefixes e.g.: `"Main.Junk" ⟶ "Junk"`"""
stripdotprefixes(str::AbstractString)  = string(last(split(str, '.')))

"""
    struct Undefined end
    const undefined = Undefined()

The singleton instance that represents a binding to an undefined value.

See also: [`getthing′`](@ref)
"""
struct Undefined end, const undefined = Undefined()

"""
    isundefined(x)

Return `true` if `x === undefined`, and return `false` if not.
"""
isundefined(::Any) = false
isundefined(::Undefined) = true

# get utilities
# -------------

using CodeTools

"""
    getfield′(mod::Module, name::AbstractString, default = undefined)
    getfield′(mod::Module, name::Symbol, default = undefined)
    getfield′(object, name::Symbol, default = undefined)
    getfield′(object, name::AbstractString, default = undefined)

Returns the specified field of a given `Module` or some arbitrary `object`,
or `default` (set to [`undefined`](@ref) by default) if no such a field is found.
"""
getfield′(mod::Module, name::AbstractString, default = undefined) = CodeTools.getthing(mod, name, default)
getfield′(mod::Module, name::Symbol, default = undefined) = getfield′(mod, string(name), default)
getfield′(@nospecialize(object), name::Symbol, default = undefined) = isdefined(object, name) ? getfield(object, name) : default
getfield′(@nospecialize(object), name::AbstractString, default = undefined) = getfield′(object, Symbol(name), default)

"""
    getmodule(mod::AbstractString)
    getmodule(parent::Union{Nothing, Module}, mod::AbstractString)
    getmodule(code::AbstractString, pos; filemod)

Calls `CodeTools.getmodule(args...)`, but returns `Main` instead of `nothing` in a fallback case.
"""
getmodule(args...) = (m = CodeTools.getmodule(args...)) === nothing ? Main : m

"""
    getmethods(mod::Module, word::AbstractString)
    getmethods(mod::AbstractString, word::AbstractString)

Returns the [`MethodList`](@ref) for `word`, which is bound within `mod` module.
"""
getmethods(mod::Module, word::AbstractString) = methods(CodeTools.getthing(mod, word))
getmethods(mod::AbstractString, word::AbstractString) = getmethods(getmodule(mod), word)

"""
    getdocs(mod::Module, word::AbstractString, fallbackmod::Module = Main)
    getdocs(mod::AbstractString, word::AbstractString, fallbackmod::Module = Main)

Retrieves docs for `mod.word` with [`@doc`](@ref) macro. If `@doc` is not available
  within `mod` module, `@doc` will be evaluated in `fallbackmod` module if possible.

!!! note
    You may want to run [`cangetdocs`](@ref) in advance.
"""
getdocs(mod::Module, word::AbstractString, fallbackmod::Module = Main) = begin
  md = if iskeyword(word)
    Core.eval(Main, :(@doc($(Symbol(word)))))
  else
    docsym = Symbol("@doc")
    if isdefined(mod, docsym)
      include_string(mod, "@doc $word")
    elseif isdefined(fallbackmod, docsym)
      word = string(mod) * "." * word
      include_string(fallbackmod, "@doc $word")
    else
      MD("@doc is not available in " * string(mod))
    end
  end
  md_hlines(md)
end
getdocs(mod::AbstractString, word::AbstractString, fallbackmod::Module = Main) =
  getdocs(getmodule(mod), word, fallbackmod)

"""
    cangetdocs(mod::Module, word::Symbol)
    cangetdocs(mod::Module, word::AbstractString)
    cangetdocs(mod::AbstractString, word::Union{Symbol, AbstractString})

Checks if the documentation bindings for `mod.word` is resolved and `mod.word`
  is not deprecated.
"""
cangetdocs(mod::Module, word::Symbol) =
  Base.isbindingresolved(mod, word) &&
  !Base.isdeprecated(mod, word)
cangetdocs(mod::Module, word::AbstractString) = cangetdocs(mod, Symbol(word))
cangetdocs(mod::AbstractString, word::Union{Symbol, AbstractString}) = cangetdocs(getmodule(mod), word)

# is utilities
# ------------

iskeyword(word::Symbol) = word in keys(Docs.keywords)
iskeyword(word::AbstractString) = iskeyword(Symbol(word))

ismacro(ct::AbstractString) = startswith(ct, '@') || endswith(ct, '"')
ismacro(f::Function) = startswith(string(methods(f).mt.name), "@")

# uri utilties
# ------------

uriopen(file, line = 0) = "atom://julia-client/?open=true&file=$(file)&line=$(line)"
uridocs(mod, word) = "atom://julia-client/?docs=true&mod=$(mod)&word=$(word)"
urigoto(mod, word) = "atom://julia-client/?goto=true&mod=$(mod)&word=$(word)"
urimoduleinfo(mod) = "atom://julia-client/?moduleinfo=true&mod=$(mod)"
