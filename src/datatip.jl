"""
Regex to match code blocks from markdown texts.
"""
const codeblock_regex = r"```((?!```).)*?```"s
"""
Regex that matches for a Julia documentation text when there is no binding exists
for the target word.
Refered to https://github.com/JuliaLang/julia/blob/master/stdlib/REPL/src/docview.jl#L152.
"""
const nobinding_regex = r"No documentation found.\n\nBinding `.*` does not exist.\n"

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

function processmethodtable!(word, mtable, datatips)
  isempty(mtable) && return

  header = "\n***\n`$(word)` has **$(length(mtable))** methods\n"

  body = map(mtable) do m
    mstring = string(m)
    text = mstring[1:match(r" at ", mstring).offset + 3]
    isbase = m.module === Base || parentmodule(m.module) === Base
    file = isbase ? basepath(string(m.file)) : m.file
    # @NOTE: Datatip service component can't handle links to file paths.
    "- $(text)$(file):$(m.line)"
  end |> lists -> join(lists, "\n")

  push!(datatips, Dict(:type  => :markdown,
                       :value => header * body))
end

function makedatatip(docs, word, mtable)
  # @FIXME?: Separates code blocks from the other markdown texts in order to
  #          render them as code snippet text by atom-ide-ui's datatip service.
  #          Setting up functions to deconstruct each `Markdown.MD.content`
  #          into an appropriate markdown string might be preferred.
  texts = split(string(docs), codeblock_regex)
  codes = searchcodeblocks(docs)

  datatips = []
  processmdtext!(texts[1], datatips)
  for (code, text) in zip(codes, texts[2:end])
    processmdcode!(code, datatips)
    processmdtext!(text, datatips)
  end
  processmethodtable!(word, mtable, datatips)

  datatips
end

handle("datatip") do data
  @destruct [mod || "Main", word] = data
  docs = @errs getdocs(mod, word)

  docs isa EvalError && return Dict(:error => true)
  # @FIXME: This is another horrible hack, may not be rubust to future documentation change.
  match(nobinding_regex, string(docs)) isa RegexMatch && return Dict(:novariable => true)

  mtable = try getmethods(mod, word)
    catch e
      []
    end

  Dict(:error   => false,
       :strings => makedatatip(docs, word, mtable))
end
