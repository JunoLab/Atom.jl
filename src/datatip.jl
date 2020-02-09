#=
@TODO use our own UI components for this:
atom-ide-ui is already deprecated, ugly, not fully functional, and and...
=#

handle("datatip") do data
  @destruct [
    word,
    mod || "Main",
    path || "",
    column || 1,
    row || 1,
    startRow || 0,
    context || ""
  ] = data
  datatip(word, mod, path, column, row, startRow, context)
end

function datatip(word, mod, path, column = 1, row = 1, startrow = 0, context = "")
  if isdebugging() && (ddt = JunoDebugger.datatip(word, path, row, column)) !== nothing
    return Dict(:error => false, :strings => ddt)
  end

  ldt = localdatatip(word, column, row, startrow, context)
  isempty(ldt) || return datatip(ldt)

  tdt = globaldatatip(mod, word)
  tdt !== nothing && return Dict(:error => false, :strings => tdt)

  return Dict(:error => true) # nothing hits
end

datatip(dt::Vector{Dict{Symbol, Any}}) = Dict(:error => false, :strings => dt)
datatip(dt::Int) = Dict(:error => false, :line => dt)
datatip(dt::Vector{Int}) = datatip(dt[1])

function localdatatip(word, column, row, startrow, context)
  word = first(split(word, '.')) # always ignore dot accessors
  position = row - startrow
  ls = locals(context, position, column)
  filter!(ls) do l
    l.name == word &&
    l.line < position
  end
  # there should be zero or one element in `ls`
  return localdatatip.(ls, word, startrow)
end

function localdatatip(l, word, startrow)
  verbatim = l.verbatim
  return if verbatim == word # when `word` is an argument or such
    startrow + l.line - 1
  else
    Dict(:type => :snippet, :value => verbatim)
  end
end

function globaldatatip(mod, word)
  docs = @errs getdocs(mod, word)
  docs isa EvalError && return nothing

  # don't show verbose stuff
  docstr = replace(string(docs), nodoc_regex => "")
  occursin(nobinding_regex, docstr) && return nothing

  datatip = []

  val = getfield′(getmodule(mod), word)
  processval!(val, docstr, datatip)

  processdoc!(docs, docstr, datatip)

  ml = methods(val)
  processmethods!(ml, datatip)

  return datatip
end

# adapted from `REPL.summarize(binding::Binding, sig)`
const nodoc_regex = r"^No documentation found."
const nobinding_regex = r"Binding `.*` does not exist.\n"

function processdoc!(docs, docstr, datatip)
  # Separate code blocks from the other markdown texts in order to render them
  # as code snippets in atom-ide-ui's datatip service.
  # Setting up functions to deconstruct each `Markdown.MD.content` into
  # an appropriate markdown string would be more robust.
  texts = split(docstr, codeblock_regex)
  codes = searchcodeblocks(docs)

  pushmarkdown!(datatip, texts[1])
  for (code, text) in zip(codes, texts[2:end])
    pushsnippet!(datatip, code)
    pushmarkdown!(datatip, text)
  end
end

# will match code blocks within a markdown text
const codeblock_regex = r"```((?!```).)*?```"s

# extract only code blocks from Markdown.MD
function searchcodeblocks(docs)
  codeblocks = []
  searchcodeblocks(docs, codeblocks)
  codeblocks
end
function searchcodeblocks(docs, codeblocks)
  for content in docs.content
    if content isa Markdown.Code
      push!(codeblocks, content.code)
    elseif content isa Markdown.MD
      searchcodeblocks(content, codeblocks)
    end
  end
end

processval!(@nospecialize(val), docstr, datatip) = begin
  valstr = @> repr(MIME("text/plain"), val, context = :limit => true) strlimit(1000, " ...")
  occursin(valstr, docstr) || pushsnippet!(datatip, valstr)
end
processval!(val::Function, docstr, datatip) = begin
  valstr = string(val) # this would get rid of the unnecessary module prefix
  occursin(valstr, docstr) || pushsnippet!(datatip, valstr)
end
processval!(::Undefined, docstr, datatip) = nothing

function processmethods!(ml, datatip)
  ms = collect(ml)
  isempty(ms) && return

  substr = s"<code>\g<sig></code> in <code>\g<mod></code> at \g<loc>"
  msstr = map(ms) do m
    s = replace(string(m), methodloc_regex => substr)
    "<li>$s</li>"
  end |> join

  name = ms[1].name
  pushmarkdown!(datatip, "<details><summary><code>$name</code> has **$(length(ms))** methods:</summary><ul>$(msstr)</ul></details>")
end

function pushmarkdown!(datatip, markdown)
  (markdown == "" || markdown == "\n") && return
  push!(datatip, Dict(:type => :markdown, :value => markdown))
end

function pushsnippet!(datatip, snippet)
  push!(datatip, Dict(:type => :snippet, :value => snippet))
end
