handle("completions") do data
  @destruct [path || nothing,
             mod || "Main",
             editorContent || "",
             lineNumber || 1,
             startLine || 0,
             column || 1,
             line, force] = data

  withpath(path) do
    m = getmodule(mod)

    cs, pre = basecompletionadapter(line, m, force, lineNumber - startLine, column, editorContent)

    Dict(:completions => cs,
         :prefix      => string(pre))
  end
end

using REPL.REPLCompletions

function basecompletionadapter(line, mod, force, lineNumber, column, text)
  comps, replace, shouldcomplete = try
    completions(line, lastindex(line), mod)
  catch err
    # might error when e.g. type inference fails
    [], 1:0, false
  end

  # Suppress completions if there are too many of them unless activated manually
  # @TODO: Checking whether `line` is a valid text to be completed in atom-julia-client
  #        in advance and drop this check
  if !force && length(comps) > MAX_COMPLETIONS
    comps = []
    replace = 1:0
  end

  pre = line[replace]
  d = []
  for c in comps
    if REPLCompletions.afterusing(line, Int(first(replace))) # need `Int` for correct dispatch on x86
      c isa REPLCompletions.PackageCompletion || continue
    end
    try
      push!(d, completion(mod, c))
    catch err
      continue
    end
  end

  # completions from the local code block:
  for c in localcompletions(text, lineNumber, column)
    if (force || !isempty(pre)) && startswith(c[:text], pre)
      pushfirst!(d, c)
    end
  end

  d, pre
end

const MAX_COMPLETIONS = 500

function completion(mod, c)
  return Dict(:type               => completiontype(c),
              :icon               => completionicon(c),
              :rightLabel         => completionmodule(mod, c),
              :leftLabel          => completionreturntype(c),
              :text               => completiontext(c),
              :description        => completionsummary(mod, c),
              :descriptionMoreURL => completionurl(c))
end

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

completionsummary(mod, c) = ""
completionsummary(mod, c::REPLCompletions.ModuleCompletion) = begin
  m, word = c.parent, c.mod
  cangetdocs(m, word) || return ""
  docs = getdocs(m, word, mod)
  description(docs)
end
completionsummary(mod, c::REPLCompletions.MethodCompletion) = begin
  ct = Symbol(c.func)
  cangetdocs(mod, ct) || return ""
  docs = try
    Docs.doc(Docs.Binding(mod, ct), Base.tuple_type_tail(c.method.sig))
  catch err
    ""
  end
  description(docs)
end
completionsummary(mod, c::REPLCompletions.KeywordCompletion) =
  description(getdocs(mod, c.keyword))

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

function localcompletions(text, line, col)
  ls = locals(text, line, col)
  reverse!(ls)
  map(localcompletion, ls)
end

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

handle("cacheCompletions") do mod
  # m = getthing(mod)
  # m = isa(m, Module) ? m : Main
  # CodeTools.completions(m)
end
