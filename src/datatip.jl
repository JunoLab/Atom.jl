#=
@FIXME?
If we come to be able to use our full-featured components in atom-julia-client
for datatips, we may want to append method tables again.
Ref: https://github.com/JunoLab/atom-julia-client/blob/master/lib/runtime/datatip.js#L3-L9
=#

handle("datatip") do data
  @destruct [mod || "Main", word] = data
  docs = @errs getdocs(mod, word)

  docs isa EvalError && return Dict(:error => true)
  occursin(nobinding_regex, string(docs)) && return Dict(:novariable => true)

  Dict(:error   => false,
       :strings => makedatatip(docs))
end

# adapted from https://github.com/JuliaLang/julia/blob/master/stdlib/REPL/src/docview.jl#L152
const nobinding_regex = r"No documentation found.\n\nBinding `.*` does not exist.\n"

function makedatatip(docs)
  # Separates code blocks from the other markdown texts in order to render  them
  # as code snippet text by atom-ide-ui's datatip service.
  # Setting up functions to deconstruct each `Markdown.MD.content` into
  # an appropriate markdown string might be preferred.
  texts = split(string(docs), codeblock_regex)
  codes = searchcodeblocks(docs)

  datatips = []
  processmdtext!(texts[1], datatips)
  for (code, text) in zip(codes, texts[2:end])
    processmdcode!(code, datatips)
    processmdtext!(text, datatips)
  end

  datatips
end

# Regex to match code blocks from markdown texts
const codeblock_regex = r"```((?!```).)*?```"s

# Extract only code blocks from Markdown.MD
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

function processmdtext!(text, datatips)
  (text == "" || text == "\n") && return
  push!(datatips, Dict(:type  => :markdown,
                       :value => text))
end

function processmdcode!(code, datatips)
  push!(datatips, Dict(:type  => :snippet,
                       :value => code))
end
