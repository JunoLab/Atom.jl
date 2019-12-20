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
    comps, prefix = basecompletionadapter(
      # general
      line, mod,
      # local context
      context, row - startRow, column,
      # configurations
      force
    )

    Dict(
      :completions => comps,
      :prefix      => prefix
    )
  end
end

using REPL.REPLCompletions

# as an heuristic, suppress completions if there are over 500 completions,
# ref: currently `completions("", 0)` returns **1132** completions as of v1.3
const SUPPRESS_COMPLETION_THRESHOLD = 500

# autocomplete-plus seems to show **200** completions at most
const MAX_COMPLETIONS = 200

function basecompletionadapter(
  # general
  line, mod = "Main",
  # local context
  context = "", row = 1, column = 1,
  # configurations
  force = false
)
  mod = getmodule(mod)

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
    end, localcompletions(context, row, column))
  else
    Dict[]
  end

  cs = cs[1:min(end, MAX_COMPLETIONS - length(comps))]
  suppresss = length(cs) > 30
  for c in cs
    if REPLCompletions.afterusing(line, Int(first(replace))) # need `Int` for correct dispatch on x86
      c isa REPLCompletions.PackageCompletion || continue
    end
    try
      push!(comps, completion(mod, c, suppresss))
    catch err
      continue
    end
  end

  return comps, prefix
end

completion(mod, c, suppress) = Dict(
  :type               => completiontype(c),
  :icon               => completionicon(c),
  :rightLabel         => completionmodule(mod, c),
  :leftLabel          => completionreturntype(c),
  :text               => completiontext(c),
  :description        => completionsummary(mod, c, suppress),
  :descriptionMoreURL => completionurl(c)
)

completiontext(c) = completion_text(c)
completiontext(c::REPLCompletions.MethodCompletion) = begin
  ct = completion_text(c)
  m = match(r"^(.*) in .*$", ct)
  m isa Nothing ? ct : m[1]
end
completiontext(c::REPLCompletions.DictCompletion) = rstrip(completion_text(c), [']', '"'])
completiontext(c::REPLCompletions.PathCompletion) = rstrip(completion_text(c), '"')

using JuliaInterpreter: sparam_syms

completionreturntype(c) = ""
completionreturntype(c::REPLCompletions.MethodCompletion) = begin
  m = c.method
  atypes = m.sig
  sparams = Core.svec(sparam_syms(m)...)
  wa = Core.Compiler.Params(typemax(UInt))  # world age
  inf = try
    Core.Compiler.typeinf_type(m, atypes, sparams, wa)
  catch err
    nothing
  end
  inf in (nothing, Any, Union{}) && return ""
  shortstr(inf)
end
completionreturntype(c::REPLCompletions.PropertyCompletion) =
  shortstr(typeof(getproperty(c.value, c.property)))
completionreturntype(c::REPLCompletions.FieldCompletion) =
  shortstr(fieldtype(c.typ, c.field))
completionreturntype(c::REPLCompletions.DictCompletion) =
  shortstr(valtype(c.dict))
completionreturntype(::REPLCompletions.PathCompletion) = "Path"

using Base.Docs

completionsummary(mod, c, suppress) = suppress ? "" : completionsummary(mod, c)
completionsummary(mod, c) = ""
completionsummary(mod, c::REPLCompletions.ModuleCompletion) = begin
  m, word = c.parent, c.mod
  cangetdocs(m, word) || return ""
  docs = getdocs(m, word, mod)
  description(docs)
end
# always show completion summary for `MethodCompletion`
completionsummary(mod, c::REPLCompletions.MethodCompletion, suppress) = begin
  ct = Symbol(c.func)
  cangetdocs(mod, ct) || return ""
  docs = try
    Docs.doc(Docs.Binding(mod, ct), Base.tuple_type_tail(c.method.sig))
  catch err
    ""
  end
  description(docs)
end
completionsummary(mod, c::REPLCompletions.KeywordCompletion) = description(getdocs(mod, c.keyword))

using Markdown

description(docs) = ""
description(docs::Markdown.MD) = begin
  md = CodeTools.flatten(docs).content
  for part in md
    if part isa Markdown.Paragraph
      desc = Markdown.plain(part)
      occursin("No documentation found.", desc) && return ""
      return strlimit(desc, 200)
    end
  end
  return ""
end

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

localcompletions(text, row, col) = localcompletion.(locals(text, row, col))

function localcompletion(l)
  return Dict(
    :type        => l[:type] == "variable" ? "attribute" : l[:type],
    :icon        => l[:icon] == "v" ? "icon-chevron-right" : l[:icon],
    :rightLabel  => l[:root],
    :leftLabel   => "",
    :text        => l[:name],
    :description => ""
  )
end
