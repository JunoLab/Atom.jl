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

  val = getfield′′(getmodule′(mod), Symbol(word))
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

function processval!(@nospecialize(val), docstr, datatip)
  # don't show value info when it's going to be described in `docstr` (might be not so robust)
  occursin(string(val), docstr) && return
  valstr = strlimit(sprint(show, val), 1000)
  pushsnippet!(datatip, valstr)
end
processval!(::Undefined, docstr, datatip) = nothing

function pushmarkdown!(datatip, markdown)
  (markdown == "" || markdown == "\n") && return
  push!(datatip, Dict(:type => :markdown, :value => markdown))
end

function pushsnippet!(datatip, snippet)
  push!(datatip, Dict(:type => :snippet, :value => snippet))
end
