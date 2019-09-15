#=
@TODO:
Use our own UI components for this: atom-ide-ui is already deprecated, ugly, not fully functional, and and...
Once we can come to handle links within datatips, we may want to append method tables as well
=#

handle("datatip") do data
  @destruct [
    word,
    mod || "Main",
    path || nothing,
    row || 1,
    column || 1
  ] = data

  if isdebugging() && (datatip = JunoDebugger.datatip(word, path, row, column)) !== nothing
    return Dict(:error => false, :strings => datatip)
  end

  docs = @errs getdocs(mod, word)
  docs isa EvalError && return Dict(:error => true)

  # don't show verbose stuff
  docstr = replace(string(docs), nodoc_regex => "")
  occursin(nobinding_regex, docstr) && return Dict(:error => true)

  datatip = []

  val = getfield′(getmodule(mod), word)
  processval!(val, docstr, datatip)

  processdoc!(docs, docstr, datatip)

  return Dict(:error => false, :strings => datatip)
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

function pushmarkdown!(datatip, markdown)
  (markdown == "" || markdown == "\n") && return
  push!(datatip, Dict(:type => :markdown, :value => markdown))
end

function pushsnippet!(datatip, snippet)
  push!(datatip, Dict(:type => :snippet, :value => snippet))
end
