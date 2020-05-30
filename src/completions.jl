import REPL.REPLCompletions, FuzzyCompletions

struct CompletionSuggestion
  replacementPrefix::String
  # suggestion body
  text::String
  type::String
  icon::String
  rightLabel::String
  leftLabel::String
  description::String
  descriptionMoreURL::String
  # for `getSuggestionDetailsOnSelect` API
  detailtype::String
end

CompletionSuggestion(prefix, text, type, icon; rl = "", ll = "", desc = "", url = "", detail = "") =
  CompletionSuggestion(prefix, text, type, icon, rl, ll, desc, url, detail)

# as an heuristic, suppress completions if there are over 500 completions,
# ref: currently `completions("", 0, Main)` returns 1098 completions as of v1.5
const SUPPRESS_COMPLETION_THRESHOLD = 500

# autocomplete-plus only shows at most 200 completions
# ref: https://github.com/atom/autocomplete-plus/blob/master/lib/suggestion-list-element.js#L49
const MAX_COMPLETIONS = 200

const DESCRIPTION_LIMIT = 200

# threshold up to which METHOD_COMPLETION_CACHE can get fat, to make sure it won't eat up memory
# NOTE: with 2000 elements it used ~10MiB on my machine.
const MAX_METHOD_COMPLETION_CACHE = 3000

# baseline completions
# --------------------

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
    is_fuzzy || true,
    force || false
  ] = data

  adapter = is_fuzzy ? fuzzycompletionadapter : replcompletionadapter
  return adapter(
    # general
    line, mod,
    # local context
    context, row - startRow, column,
    # configurations
    force
  )::Vector{CompletionSuggestion}
end

# NOTE:
# `replcompletionadapter` and `fuzzycompletionadapter` are really similar
# and maybe better to be refactored into a single function,
# but we define them as separate functions for type-stabilities for now

function replcompletionadapter(
  # general
  line, m = "Main",
  # local context
  context = "", row = 1, column = 1,
  # configurations
  force = false
)
  mod = getmodule(m)

  cs, replace, shouldcomplete = try
    REPLCompletions.completions(line, lastindex(line), mod)
  catch err
    # might error when e.g. type inference fails
    REPLCompletions.Completion[], 1:0, false
  end
  prefix = line[replace]

  # suppress completions if there are still too many of them i.e. when invoked with `$|`, `(|`, etc.
  # XXX: the heuristics below mayn't be so robust to work for all the cases.
  !force && (isempty(prefix) && length(cs) > SUPPRESS_COMPLETION_THRESHOLD) && (cs = REPLCompletions.Completion[])

  # initialize suggestions with local completions so that they show up first
  comps = if force || !isempty(prefix)
    filter!(let p = prefix
      c -> startswith(c.text, p)
    end, localcompletions(context, row, column, prefix))
  else
    CompletionSuggestion[]
  end

  # FIFO cache refreshing
  if length(METHOD_COMPLETION_CACHE) ≥ MAX_METHOD_COMPLETION_CACHE
    for k in collect(keys(METHOD_COMPLETION_CACHE))[1:MAX_METHOD_COMPLETION_CACHE÷2]
      delete!(METHOD_COMPLETION_CACHE, k)
    end
  end

  @inbounds cs = cs[1:min(end, MAX_COMPLETIONS - length(comps))]
  afterusing = REPLCompletions.afterusing(line, Int(first(replace))) # need `Int` for correct dispatch on x86
  for c in cs
    if afterusing
      c isa REPLCompletions.PackageCompletion || continue
    end
    push!(comps, completion(mod, c, prefix))
  end

  return comps
end

function fuzzycompletionadapter(
  # general
  line, m = "Main",
  # local context
  context = "", row = 1, column = 1,
  # configurations
  force = false
)
  mod = getmodule(m)

  cs, replace, shouldcomplete = try
    FuzzyCompletions.completions(line, lastindex(line), mod)
  catch err
    # might error when e.g. type inference fails
    FuzzyCompletions.Completion[], 1:0, false
  end
  prefix = line[replace]

  if !force
    filter!(c -> FuzzyCompletions.score(c) ≥ 0, cs) # filter negative scores

    # suppress completions if there are still too many of them i.e. when invoked with `$|`, `(|`, etc.
    # XXX: the heuristics below mayn't be so robust to work for all the cases.
    (isempty(prefix) && length(cs) > SUPPRESS_COMPLETION_THRESHOLD) && (cs = FuzzyCompletions.Completion[])
  end

  # initialize suggestions with local completions so that they show up first
  comps = localcompletions(context, row, column, prefix)
  if !force
    filter!(let p = prefix
      # NOTE: let's be a bit strict on local completions so that we avoid verbose completions, e.g. troublemaker cases
      comp -> FuzzyCompletions.fuzzyscore(p, comp.text) > 0
    end, comps)
  end

  # FIFO cache refreshing
  if length(METHOD_COMPLETION_CACHE) ≥ MAX_METHOD_COMPLETION_CACHE
    for k in collect(keys(METHOD_COMPLETION_CACHE))[1:MAX_METHOD_COMPLETION_CACHE÷2]
      delete!(METHOD_COMPLETION_CACHE, k)
    end
  end

  @inbounds cs = cs[1:min(end, MAX_COMPLETIONS - length(comps))]
  afterusing = FuzzyCompletions.afterusing(line, Int(first(replace))) # need `Int` for correct dispatch on x86
  for c in cs
    if afterusing
      c isa FuzzyCompletions.PackageCompletion || continue
    end
    push!(comps, completion(mod, c, prefix))
  end

  return comps
end

# for functions below works both for REPLCompletions and FuzzyCompletions modules
for c in [:KeywordCompletion, :PathCompletion, :ModuleCompletion, :PackageCompletion,
          :PropertyCompletion, :FieldCompletion, :MethodCompletion, :BslashCompletion,
          :ShellCompletion, :DictCompletion]
  eval(:(const $c = Union{REPLCompletions.$c, FuzzyCompletions.$c}))
end
completion_text(c::REPLCompletions.Completion) = REPLCompletions.completion_text(c)
completion_text(c::FuzzyCompletions.Completion) = FuzzyCompletions.completion_text(c)

completion(mod, c, prefix) =
  CompletionSuggestion(
    prefix, completiontext(c), completiontype(c), completionicon(c);
    rl = completionmodule(mod, c), ll = completionreturntype(c), url = completionurl(c), detail = completiondetailtype(c)
  )

const MethodCompletionInfo = NamedTuple{(:f,:m,:tt),Tuple{Any,Method,Type}}
const MethodCompletionDetail = NamedTuple{(:rt,:desc),Tuple{String,String}}
"""
    METHOD_COMPLETION_CACHE::OrderedDict{String,Union{MethodCompletionInfo,MethodCompletionDetail}}
    MethodCompletionInfo = NamedTuple{(:f,:m,:tt),Tuple{Any,Method,Type}}
    MethodCompletionDetail = NamedTuple{(:rt,:desc),Tuple{String,String}}

[`OrderedCollections.OrderedDict`](@ref) that caches details of [`MethodCompletion`](@ref)s:
- result of a return type inference
- documentation description

This cache object has the following structure:
Keys are hash `String` of a `MethodCompletion` object,
  which can be used for cache detection or refered lazily by
  [autocompluete-plus's `getSuggestionDetailsOnSelect` API]
  (https://github.com/atom/autocomplete-plus/wiki/Provider-API#defining-a-provider)
Values can be either of:
- `MethodCompletionInfo`: keeps (temporary) information of this `MethodCompletion`
  + `f`: a function object
  + `m`: a `Method` object
  + `tt`: an input `Tuple` type
- `MethodCompletionDetail`: stores the lazily computed detail of this `MethodCompletion`
  + `rt`: `String` representing a return type of this method call
  + `desc`: `String` representing documentation of this method

If the second element is still a `MethodCompletionInfo` instance, that means its details
  aren't lazily computed yet.
If the second element is already a `MethodCompletionDetail` then we can reuse this cache.

!!! note
    If a method gets updated (i.e. redefined etc), key hash for the `MethodCompletion`
      will be different from the previous one, so it's okay if we just rely on the hash key.

!!! warning
    Within the current implementation, we can't reflect changes that happens in backedges.
"""
const METHOD_COMPLETION_CACHE = OrderedDict{String,Union{MethodCompletionInfo,MethodCompletionDetail}}()

function completion(mod, c::MethodCompletion, prefix)
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
    METHOD_COMPLETION_CACHE[k] = info
    rt, desc = "", ""
    dt = k
  end

  return CompletionSuggestion(
    prefix, completiontext(c), completiontype(c), completionicon(c);
    rl = completionmodule(mod, c), ll = rt, desc = desc, url = completionurl(c), detail = dt
  )
end

completiontext(c) = completion_text(c)
completiontext(c::MethodCompletion) = begin
  ct = completion_text(c)
  m = match(r"^(.*) in .*$", ct)
  m isa Nothing ? ct : m[1]
end
completiontext(c::DictCompletion) = rstrip(completion_text(c), [']', '"'])
completiontext(c::PathCompletion) = rstrip(completion_text(c), '"')

completionreturntype(c) = ""
completionreturntype(c::PropertyCompletion) = begin
  isdefined(c.value, c.property) || return ""
  shortstr(typeof(getproperty(c.value, c.property)))
end
completionreturntype(c::FieldCompletion) =
  shortstr(fieldtype(c.typ, c.field))
completionreturntype(c::DictCompletion) =
  shortstr(valtype(c.dict))
completionreturntype(::PathCompletion) = "Path"

completionurl(c) = ""
completionurl(c::ModuleCompletion) = begin
  mod, name = c.parent, c.mod
  val = getfield′(mod, name)
  if val isa Module # module info
    urimoduleinfo(parentmodule(val) == val || val ∈ (Base, Core) ? name : "$mod.$name")
  else
    uridocs(mod, name)
  end
end
completionurl(c::MethodCompletion) = uridocs(c.method.module, c.method.name)
completionurl(c::PackageCompletion) = urimoduleinfo(c.package)
completionurl(c::KeywordCompletion) = uridocs("Main", c.keyword)

completionmodule(mod, c) = shortstr(mod)
completionmodule(mod, c::ModuleCompletion) = shortstr(c.parent)
completionmodule(mod, c::MethodCompletion) = shortstr(c.method.module)
completionmodule(mod, c::FieldCompletion) = shortstr(c.typ) # predicted type
completionmodule(mod, ::KeywordCompletion) = ""
completionmodule(mod, ::PathCompletion) = ""

completiontype(c) = "variable"
completiontype(c::ModuleCompletion) = begin
  ct = completion_text(c)
  ismacro(ct) && return "snippet"
  mod, name = c.parent, Symbol(ct)
  val = getfield′(mod, name)
  wstype(mod, name, val)
end
completiontype(::MethodCompletion) = "method"
completiontype(::PackageCompletion) = "import"
completiontype(::PropertyCompletion) = "property"
completiontype(::FieldCompletion) = "property"
completiontype(::DictCompletion) = "property"
completiontype(::KeywordCompletion) = "keyword"
completiontype(::PathCompletion) = "path"

completionicon(c) = ""
completionicon(c::ModuleCompletion) = begin
  ismacro(c.mod) && return "icon-mention"
  mod, name = c.parent, Symbol(c.mod)
  val = getfield′(mod, name)
  wsicon(mod, name, val)
end
completionicon(::DictCompletion) = "icon-key"
completionicon(::PathCompletion) = "icon-file"

completiondetailtype(c) = ""
completiondetailtype(::ModuleCompletion) = "module"
completiondetailtype(::KeywordCompletion) = "keyword"

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
  type = (type = static_type(l)) == "variable" ? "attribute" : type
  icon = (icon = static_icon(l)) == "v" ? "icon-chevron-right" : icon
  return CompletionSuggestion(
    prefix, l.name, type, icon;
    rl = l.root, desc = desc, detail = ""
  )
end

# completion details
# ------------------

function completiondetail!(comp)
  dt = comp["detailtype"]::String
  isempty(dt) && return comp
  word = comp["text"]::String

  if dt == "module"
    mod = comp["rightLabel"]::String
    completiondetail_module!(comp, mod, word)
  elseif dt == "keyword"
    completiondetail_keyword!(comp, word)
  else # detail for method completion
    completiondetail_method!(comp, dt)
  end

  comp["detailtype"] = "" # may not be needed, but empty this to make sure any further detail completion doesn't happen
  return comp
end

handle(completiondetail!, "completiondetail")

function completiondetail_module!(comp, mod, word)
  mod = getmodule(mod)
  cangetdocs(mod, word) || return
  comp["description"] = completiondescription(getdocs(mod, word))
end

completiondetail_keyword!(comp, word) =
  comp["description"] = completiondescription(getdocs(Main, word))

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
    comp["leftLabel"] = v.rt
    comp["description"] = v.desc
    return
  end
  f, m, tt = v.f, v.m, v.tt

  # return type inference
  rt = rt_inf(f, m, Base.tuple_type_tail(tt))
  comp["leftLabel"] = rt

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
  comp["description"] = desc

  # update method completion cache with the results

  METHOD_COMPLETION_CACHE[k] = MethodCompletionDetail((rt = rt, desc = desc))
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
    inf = @static if isdefined(Core.Compiler, :NativeInterpreter)
      Core.Compiler.typeinf_type(Core.Compiler.NativeInterpreter(), m, m.sig, sparams)
    else
      Core.Compiler.typeinf_type(m, m.sig, sparams, Core.Compiler.Params(world))
    end
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
