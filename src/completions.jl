### baseline completions ###

handle("completions") do data
  @destruct [
    # general
    line,
    mod || "Main",
    path || nothing,
    # local context
    context || "",
    row || 1,
    startRow || 0,
    column || 1,
    # configurations
    force || false
  ] = data

  withpath(path) do
    basecompletionadapter(
      # general
      line, mod,
      # local context
      context, row - startRow, column,
      # configurations
      force
    )
  end
end

using REPL.REPLCompletions

const CompletionSuggetion = Dict{Symbol, String}

# as an heuristic, suppress completions if there are over 500 completions,
# ref: currently `completions("", 0)` returns **1132** completions as of v1.3
const SUPPRESS_COMPLETION_THRESHOLD = 500

# autocomplete-plus only shows at most 200 completions
# ref: https://github.com/atom/autocomplete-plus/blob/master/lib/suggestion-list-element.js#L49
const MAX_COMPLETIONS = 200

const DESCRIPTION_LIMIT = 200

# threshold up to which METHOD_COMPLETION_CACHE can get fat, to make sure it won't eat up memory
# NOTE: with 2000 elements it used ~10MiB on my machine.
const MAX_METHOD_COMPLETION_CACHE = 2000

function basecompletionadapter(
  # general
  line, m = "Main",
  # local context
  context = "", row = 1, column = 1,
  # configurations
  force = false
)
  mod = getmodule(m)

  cs, replace, shouldcomplete = try
    completions(line, lastindex(line), mod)
  catch err
    # might error when e.g. type inference fails
    REPLCompletions.Completion[], 1:0, false
  end

  # suppress completions if there are too many of them unless activated manually
  # e.g. when invoked with `$|`, `(|`, etc.
  # TODO: check whether `line` is a valid text to complete in frontend
  if !force && length(cs) > SUPPRESS_COMPLETION_THRESHOLD
    cs = REPLCompletions.Completion[]
    replace = 1:0
  end

  # initialize suggestions with local completions so that they show up first
  prefix = line[replace]
  comps = if force || !isempty(prefix)
    filter!(let p = prefix
      c -> startswith(c[:text], p)
    end, localcompletions(context, row, column, prefix))
  else
    CompletionSuggetion[]
  end

  length(METHOD_COMPLETION_CACHE) ≥ MAX_METHOD_COMPLETION_CACHE && empty!(METHOD_COMPLETION_CACHE)

  cs = cs[1:min(end, MAX_COMPLETIONS - length(comps))]
  afterusing = REPLCompletions.afterusing(line, Int(first(replace))) # need `Int` for correct dispatch on x86
  for c in cs
    if afterusing
      c isa REPLCompletions.PackageCompletion || continue
    end
    push!(comps, completion(mod, c, prefix))
  end

  return comps
end

completion(mod, c, prefix) = CompletionSuggetion(
  :replacementPrefix  => prefix,
  # suggestion body
  :text               => completiontext(c),
  :type               => completiontype(c),
  :icon               => completionicon(c),
  :rightLabel         => completionmodule(mod, c),
  :leftLabel          => completionreturntype(c),
  :descriptionMoreURL => completionurl(c),
  # for `getSuggestionDetailsOnSelect` API
  :detailtype         => completiondetailtype(c)
)

const MethodCompletionInfo = NamedTuple{(:f,:m,:tt),Tuple{Any,Method,Type}}
const MethodCompletionDetail = NamedTuple{(:rt,:desc),Tuple{String,String}}
"""
    METHOD_COMPLETION_CACHE::Dict{String,Union{MethodCompletionInfo,MethodCompletionDetail}}
    MethodCompletionInfo = NamedTuple{(:f,:m,:tt),Tuple{Any,Method,Type}}
    MethodCompletionDetail = NamedTuple{(:rt,:desc),Tuple{String,String}}

`Dict` that caches details of `REPLCompletions.MethodCompletion`s:
- result of a return type inference
- documentation description

This cache object has the following structure:
Keys are hash `String` of a `REPLCompletions.MethodCompletion` object,
  which can be used for cache detection or refered lazily by
  [autocompluete-plus's `getSuggestionDetailsOnSelect` API]
  (https://github.com/atom/autocomplete-plus/wiki/Provider-API#defining-a-provider)
Values can be either of:
- `MethodCompletionInfo`: keeps (temporary) information of this `REPLCompletions.MethodCompletion`
  + `f`: a function object
  + `m`: a `Method` object
  + `tt`: an input `Tuple` type
- `MethodCompletionDetail`: stores the lazily computed detail of this `REPLCompletions.MethodCompletion`
  + `rt`: `String` representing a return type of this method call
  + `desc`: `String` representing documentation of this method

If the second element is still a `MethodCompletionInfo` instance, that means its details
  aren't lazily computed yet.
If the second element is already a `MethodCompletionDetail` then we can reuse this cache.

!!! note
    If a method gets updated (i.e. redefined etc), key hash for the `REPLCompletions.MethodCompletion`
      will be different from the previous one, so it's okay if we just rely on the hash key.

!!! warning
    Within the current implementation, we can't reflect changes that happens in backedges.
"""
const METHOD_COMPLETION_CACHE = Dict{String,Union{MethodCompletionInfo,MethodCompletionDetail}}()

function completion(mod, c::REPLCompletions.MethodCompletion, prefix)
  k = repr(hash(c))

  m = c.method
  v = get(METHOD_COMPLETION_CACHE, k, nothing)
  if v !== nothing
    if v isa MethodCompletionDetail
      # cache found
      rt, desc = v
      dt = ""
    else
      # MethodCompletion information has already been stored, but lazy return type inference and
      # description completement has not been done yet
      rt, desc = "", ""
      dt = k
    end
  else
    # store MethodCompletion information for lazy return type inference and description completement
    info = MethodCompletionInfo((
      f = c.func,
      m = m,
      tt = c.input_types
    ))
    push!(METHOD_COMPLETION_CACHE, k => info)
    rt, desc = "", ""
    dt = k
  end

  return CompletionSuggetion(
    :replacementPrefix  => prefix,
    # suggestion body
    :text               => completiontext(c),
    :type               => completiontype(c),
    :icon               => completionicon(c),
    :rightLabel         => completionmodule(mod, c),
    :leftLabel          => rt,
    :description        => desc,
    :descriptionMoreURL => completionurl(c),
    # for `getSuggestionDetailsOnSelect` API
    :detailtype         => dt
  )
end

completiontext(c) = completion_text(c)
completiontext(c::REPLCompletions.MethodCompletion) = begin
  ct = completion_text(c)
  m = match(r"^(.*) in .*$", ct)
  m isa Nothing ? ct : m[1]
end
completiontext(c::REPLCompletions.DictCompletion) = rstrip(completion_text(c), [']', '"'])
completiontext(c::REPLCompletions.PathCompletion) = rstrip(completion_text(c), '"')

completionreturntype(c) = ""
completionreturntype(c::REPLCompletions.PropertyCompletion) = begin
  isdefined(c.value, c.property) || return ""
  shortstr(typeof(getproperty(c.value, c.property)))
end
completionreturntype(c::REPLCompletions.FieldCompletion) =
  shortstr(fieldtype(c.typ, c.field))
completionreturntype(c::REPLCompletions.DictCompletion) =
  shortstr(valtype(c.dict))
completionreturntype(::REPLCompletions.PathCompletion) = "Path"

completionurl(c) = ""
completionurl(c::REPLCompletions.ModuleCompletion) = begin
  mod, name = c.parent, c.mod
  val = getfield′(mod, name)
  if val isa Module # module info
    urimoduleinfo(parentmodule(val) == val || val ∈ (Base, Core) ? name : "$mod.$name")
  else
    uridocs(mod, name)
  end
end
completionurl(c::REPLCompletions.MethodCompletion) = uridocs(c.method.module, c.method.name)
completionurl(c::REPLCompletions.PackageCompletion) = urimoduleinfo(c.package)
completionurl(c::REPLCompletions.KeywordCompletion) = uridocs("Main", c.keyword)

completionmodule(mod, c) = shortstr(mod)
completionmodule(mod, c::REPLCompletions.ModuleCompletion) = shortstr(c.parent)
completionmodule(mod, c::REPLCompletions.MethodCompletion) = shortstr(c.method.module)
completionmodule(mod, c::REPLCompletions.FieldCompletion) = shortstr(c.typ) # predicted type
completionmodule(mod, ::REPLCompletions.KeywordCompletion) = ""
completionmodule(mod, ::REPLCompletions.PathCompletion) = ""

completiontype(c) = "variable"
completiontype(c::REPLCompletions.ModuleCompletion) = begin
  ct = completion_text(c)
  ismacro(ct) && return "snippet"
  mod, name = c.parent, Symbol(ct)
  val = getfield′(mod, name)
  wstype(mod, name, val)
end
completiontype(::REPLCompletions.MethodCompletion) = "method"
completiontype(::REPLCompletions.PackageCompletion) = "import"
completiontype(::REPLCompletions.PropertyCompletion) = "property"
completiontype(::REPLCompletions.FieldCompletion) = "property"
completiontype(::REPLCompletions.DictCompletion) = "property"
completiontype(::REPLCompletions.KeywordCompletion) = "keyword"
completiontype(::REPLCompletions.PathCompletion) = "path"

completionicon(c) = ""
completionicon(c::REPLCompletions.ModuleCompletion) = begin
  ismacro(c.mod) && return "icon-mention"
  mod, name = c.parent, Symbol(c.mod)
  val = getfield′(mod, name)
  wsicon(mod, name, val)
end
completionicon(::REPLCompletions.DictCompletion) = "icon-key"
completionicon(::REPLCompletions.PathCompletion) = "icon-file"

completiondetailtype(c) = ""
completiondetailtype(::REPLCompletions.ModuleCompletion) = "module"
completiondetailtype(::REPLCompletions.KeywordCompletion) = "keyword"

function localcompletions(context, row, col, prefix)
  ls = locals(context, row, col)
  lines = split(context, '\n')
  return localcompletion.(ls, prefix, Ref(lines))
end
function localcompletion(l, prefix, lines)
  desc = if l.verbatim == l.name
    # show a line as is if ActualLocalBinding.verbatim is not so informative
    lines[l.line]
  else
    l.verbatim
  end |> s -> strlimit(s, DESCRIPTION_LIMIT)
  return CompletionSuggetion(
    :replacementPrefix  => prefix,
    # suggestion body
    :text               => l.name,
    :type               => (type = static_type(l)) == "variable" ? "attribute" : type,
    :icon               => (icon = static_icon(l)) == "v" ? "icon-chevron-right" : icon,
    :rightLabel         => l.root,
    :description        => desc,
    # for `getSuggestionDetailsOnSelect` API
    :detailtype         => "", # shouldn't complete
  )
end

### completion details on selection ###

handle("completiondetail") do _comp
  comp = Dict(Symbol(k) => v for (k, v) in _comp)
  completiondetail!(comp)
  return comp
end

function completiondetail!(comp)
  dt = comp[:detailtype]::String
  isempty(dt) && return comp
  word = comp[:text]::String

  if dt == "module"
    mod = comp[:rightLabel]::String
    completiondetail_module!(comp, mod, word)
  elseif dt == "keyword"
    completiondetail_keyword!(comp, word)
  else # detail for method completion
    completiondetail_method!(comp, dt)
  end

  comp[:detailtype] = "" # may not be needed, but empty this to make sure any further detail completion doesn't happen
end

function completiondetail_module!(comp, mod, word)
  mod = getmodule(mod)
  cangetdocs(mod, word) || return
  comp[:description] = completiondescription(getdocs(mod, word))
end

completiondetail_keyword!(comp, word) =
  comp[:description] = completiondescription(getdocs(Main, word))

using JuliaInterpreter: sparam_syms
using Base.Docs

function completiondetail_method!(comp, k)
  v = get(METHOD_COMPLETION_CACHE, k, nothing)
  v === nothing && return # shouldn't happen but just to make sure and help type inference
  if v isa MethodCompletionDetail
    # NOTE
    # This path sometimes happens maybe because of some lags between Juno and getSuggestionDetailsOnSelect API,
    # especially just after we booted Julia, and there are not so much inference caches in the Julia internal.
    # But since details are computed, we can just use here as well
    comp[:leftLabel] = v.rt
    comp[:description] = v.desc
    return
  end
  f, m, tt = v.f, v.m, v.tt

  # return type inference
  rt = rt_inf(f, m, Base.tuple_type_tail(tt))
  comp[:leftLabel] = rt

  # description for this method
  mod = m.module
  fsym = m.name
  desc = if cangetdocs(mod, fsym)
    try
      docs = Docs.doc(Docs.Binding(mod, fsym), Base.tuple_type_tail(m.sig))
      completiondescription(docs)
    catch
      ""
    end
  else
    ""
  end
  comp[:description] = desc

  # update method completion cache with the results
  push!(METHOD_COMPLETION_CACHE, k => MethodCompletionDetail((
    rt = rt,
    desc = desc
  )))
end

function rt_inf(@nospecialize(f), m, @nospecialize(tt::Type))
  try
    world = typemax(UInt) # world age

    # first infer return type using input types
    # NOTE:
    # since input types are all concrete, the inference result from them is the best what we can get
    # so here we eagerly respect that if inference succeeded
    if !isempty(tt.parameters)
      inf = Core.Compiler.return_type(f, tt, world)
      inf ∉ (nothing, Any, Union{}) && return shortstr(inf)
    end

    # sometimes method signature can tell the return type by itself
    sparams = Core.svec(sparam_syms(m)...)
    inf = Core.Compiler.typeinf_type(m, m.sig, sparams, Core.Compiler.Params(world))
    inf ∉ (nothing, Any, Union{}) && return shortstr(inf)
  catch err
    # @error err
  end
  return ""
end

using Markdown

completiondescription(docs) = ""
completiondescription(docs::Markdown.MD) = begin
  md = CodeTools.flatten(docs).content
  for part in md
    if part isa Markdown.Paragraph
      desc = Markdown.plain(part)
      occursin("No documentation found.", desc) && return ""
      return strlimit(desc, DESCRIPTION_LIMIT)
    end
  end
  return ""
end
