import REPL.REPLCompletions, FuzzyCompletions

struct CompletionSuggestion
  replacementPrefix::String
  # suggestion body
  text::String
  type::String
  icon::String
  rightLabel::String
  rightLabelHTML::String
  leftLabel::String
  leftLabelHTML::String
  description::String
  descriptionMoreURL::String
  # for `getSuggestionDetailsOnSelect` API
  detailtype::String
end

function CompletionSuggestion(prefix, text, type, icon; rl = "", ll = "", desc = "", url = "", detail = "")
  CompletionSuggestion(prefix, text, type, icon, rl, codehtml(rl), ll, codehtml(ll), desc, url, detail)
end
codehtml(s) = isempty(s) ? "" : string("<span><code>", s, "</code></span>") # don't create empty HTML

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

@inbounds function replcompletionadapter(
  # general
  line, m = "Main",
  # local context
  context = "", row = 1, column = 1,
  # configurations
  force = false
)
  mod = getmodule(m)

  cs, replace, shouldcomplete = try
    @static if hasmethod(REPLCompletions.completions, (String,Int,Module,Bool))
      REPLCompletions.completions(line, lastindex(line), mod, force)
    else
      REPLCompletions.completions(line, lastindex(line), mod)
    end
  catch
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

  # mimic the filter https://github.com/JuliaLang/julia/blob/c3c9540ff87f49347009bb14430606102b308460/stdlib/REPL/src/REPL.jl#L489-L496
  @static if isdefined(LineEdit, :Modifiers)
    if is38791(line[1:lastindex(line)]) && !force
      # Filter out methods where all arguments are `Any`
      filter!(cs) do c
        isa(c, MethodCompletion) || return true
        sig = Base.unwrap_unionall(c.method.sig)::DataType
        return !all(T -> T === Any || T === Vararg{Any}, sig.parameters[2:end])
      end
    end
  end
  cs = cs[1:min(end, MAX_COMPLETIONS - length(comps))]
  REPLCompletions.afterusing(line, Int(first(replace))) && filter!(ispkgcomp, cs) # need `Int` for correct dispatch on x86
  append!(comps, completion.(Ref(mod), cs, prefix))

  return comps
end

@inbounds function fuzzycompletionadapter(
  # general
  line, m = "Main",
  # local context
  context = "", row = 1, column = 1,
  # configurations
  force = false
)
  mod = getmodule(m)

  cs, replace, shouldcomplete = try
    @static if hasmethod(FuzzyCompletions.completions, (String,Int,Module,Bool))
      FuzzyCompletions.completions(line, lastindex(line), mod, force)
    else
      FuzzyCompletions.completions(line, lastindex(line), mod)
    end
  catch
    # might error when e.g. type inference fails
    FuzzyCompletions.Completion[], 1:0, false
  end
  prefix = line[replace]

  if !force
    filter!(c -> !isa(c, FilterableCompletions) || FuzzyCompletions.score(c) ≥ 0, cs) # filter negative scores

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

  # mimic the filter https://github.com/JuliaLang/julia/blob/c3c9540ff87f49347009bb14430606102b308460/stdlib/REPL/src/REPL.jl#L489-L496
  @static if isdefined(LineEdit, :Modifiers)
    if is38791(line[1:lastindex(line)]) && !force
      # Filter out methods where all arguments are `Any`
      filter!(cs) do c
        isa(c, MethodCompletion) || return true
        sig = Base.unwrap_unionall(c.method.sig)::DataType
        return !all(T -> T === Any || T === Vararg{Any}, sig.parameters[2:end])
      end
    end
  end
  cs = cs[1:min(end, MAX_COMPLETIONS - length(comps))]
  REPLCompletions.afterusing(line, Int(first(replace))) && filter!(ispkgcomp, cs) # need `Int` for correct dispatch on x86
  append!(comps, completion.(Ref(mod), cs, prefix))

  return comps
end

# adapted from https://github.com/JuliaLang/julia/blob/c3c9540ff87f49347009bb14430606102b308460/stdlib/REPL/src/REPLCompletions.jl#L701-L729
function is38791(partial)
    # ?(x, y)TAB lists methods you can call with these objects
    # ?(x, y TAB lists methods that take these objects as the first two arguments
    # MyModule.?(x, y)TAB restricts the search to names in MyModule
    rexm = match(r"(\w+\.|)\?\((.*)$", partial)
    if rexm !== nothing
        moreargs = !endswith(rexm.captures[2], ')')
        callstr = "_(" * rexm.captures[2]
        if moreargs
            callstr *= ')'
        end
        ex_org = Meta.parse(callstr, raise=false, depwarn=false)
        if isa(ex_org, Expr)
            return true
        end
    end
    return false
end

const FilterableCompletions = Union{
  FuzzyCompletions.KeywordCompletion,
  FuzzyCompletions.ModuleCompletion,
}

# for functions below works both for REPLCompletions and FuzzyCompletions modules
for c in [:KeywordCompletion, :PathCompletion, :ModuleCompletion, :PackageCompletion,
          :PropertyCompletion, :FieldCompletion, :MethodCompletion, :BslashCompletion,
          :ShellCompletion, :DictCompletion]
  eval(:(const $c = Union{REPLCompletions.$c, FuzzyCompletions.$c}))
end
completion_text(c::REPLCompletions.Completion) = REPLCompletions.completion_text(c)
completion_text(c::FuzzyCompletions.Completion) = FuzzyCompletions.completion_text(c)

const ispkgcomp = Base.Fix2(isa, PackageCompletion)

completion(mod, c, prefix) =
  CompletionSuggestion(
    prefix, completiontext(c), completiontype(c), completionicon(c);
    rl = completionmodule(mod, c), ll = completionreturntype(c), url = completionurl(c), detail = completiondetailtype(c)
  )

struct MethodCompletionInfo
  tt
  m::Method
  MethodCompletionInfo(@nospecialize(tt), m::Method) = new(tt, m)
end

struct MethodCompletionDetail
  rt::String
  desc::String
end

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

  v = get(METHOD_COMPLETION_CACHE, k, nothing)
  if v !== nothing
    if v isa MethodCompletionDetail
      # cache found
      rt, desc = v.rt, v.desc
      dt = ""
    else
      # MethodCompletion information has already been stored, but lazy return type inference and
      # description completement has not been done yet
      rt, desc = "", ""
      dt = k
    end
  else
    # store MethodCompletion information for lazy return type inference and description completement
    m = c.method
    @static if VERSION ≥ v"1.8.0-DEV.1419"
      tt = c.tt
    else
      if isa(c, FuzzyCompletions.MethodCompletion)
        tt = c.tt
      else
        c.input_types
      end
    end
    info = MethodCompletionInfo(tt, m)
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
completionmodule(mod, c::PropertyCompletion) = shortstr(typeof(c.value))
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

using Markdown

description(docs) = ""
description(docs::Markdown.MD) = begin
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

handle(completiondetail!, "completiondetail")

function completiondetail_module!(comp, mod, word)
  mod = getmodule(mod)
  cangetdocs(mod, word) || return
  comp["description"] = description(getdocs(mod, word))
end

const KEYWORD_DESCRIPTIONS = Dict(k => description(getdocs(Main, k)) for k in string.(keys(Docs.keywords)))

completiondetail_keyword!(comp, word) = comp["description"] = get(KEYWORD_DESCRIPTIONS, word, "")

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
    comp["leftLabelHTML"] = codehtml(v.rt)
    comp["description"] = v.desc
    return
  end
  m, tt = v.m, v.tt

  # return type inference
  rt = rt_inf(m, tt)
  comp["leftLabel"] = rt
  comp["leftLabelHTML"] = codehtml(rt)

  # description for this method
  mod = m.module
  fsym = m.name
  desc = if cangetdocs(mod, fsym)
    try
      docs = Docs.doc(Docs.Binding(mod, fsym), Base.tuple_type_tail(m.sig))
      description(docs)
    catch
      ""
    end
  else
    ""
  end
  comp["description"] = desc

  # update method completion cache with the results

  METHOD_COMPLETION_CACHE[k] = MethodCompletionDetail(rt, desc)
end

function rt_inf(m, @nospecialize(tt))
  try
    world = Base.get_world_counter() # world age

    interp = Core.Compiler.NativeInterpreter(world)

    # first infer return type using input types
    # NOTE:
    # since input types are all concrete, the inference result from them is the best what we can get
    # so here we eagerly respect that if inference succeeded
    inf = return_type(interp, tt)
    inf ∉ (nothing, Any, Union{}) && return shortstr(inf)

    # sometimes method signature can tell the return type by itself
    sparams = sparams_from_method_signature(m)
    inf = Core.Compiler.typeinf_type(interp, m, m.sig, sparams)
    inf ∉ (nothing, Any, Union{}) && return shortstr(inf)
  catch err
    # @error err
  end
  return ""
end

function sparams_from_method_signature(m)
  s = TypeVar[]
  sig = m.sig
  while sig isa UnionAll
    push!(s, sig.var)
    sig = sig.body
  end
  return Core.svec(s...)
end

function return_type(interp::Core.Compiler.AbstractInterpreter, @nospecialize(t))
  isa(t, DataType) || return Any
  rt = Union{}
  f = Core.Compiler.singleton_type(t.parameters[1])
  if isa(f, Core.Builtin)
    args = Any[t.parameters...]
    popfirst!(args)
    rt = Core.Compiler.builtin_tfunction(interp, f, args, nothing)
    rt = Core.Compiler.widenconst(rt)
  else
    for match in Core.Compiler._methods_by_ftype(t, -1, Core.Compiler.get_world_counter(interp))::Vector
      match = match::Core.MethodMatch
      ty = Core.Compiler.typeinf_type(interp, match.method, match.spec_types, match.sparams)
      ty === nothing && return Any
      rt = Core.Compiler.tmerge(rt, ty)
      rt === Any && break
    end
  end
  return rt
end
