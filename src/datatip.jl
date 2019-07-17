# Extract only code blocks from Markdown.MD
function searchcodeblocks(md)
  codeblocks = []
  searchcodeblocks(md, codeblocks)
  codeblocks
end
function searchcodeblocks(md, codeblocks)
  for content in md.content
    if content isa Markdown.Code
      push!(codeblocks, content.code)
    elseif content isa Markdown.MD
      searchcodeblocks(content, codeblocks)
    end
  end
end

function processmdtext!(text, docstrings)
  (text == "" || text == "\n") && return
  push!(docstrings, Dict(:type  => :markdown,
                         :value => text))
end

function processmdcode!(code, docstrings)
  push!(docstrings, Dict(:type  => :snippet,
                         :value => code))
end

function processmethodtable!(word, mtable, docstrings)
  isempty(mtable) && return

  header = "\n***\n`$(word)` has **$(length(mtable))** methods\n"

  body = map(mtable) do m
    mstring = string(m)
    text = mstring[1:match(r" at ", mstring).offset + 3]
    isbase = m.module === Base || parentmodule(m.module) === Base
    file = isbase ? basepath(string(m.file)) : m.file
    # @NOTE: Datatip service component can't handle links
    "- $(text)$(file):$(m.line)"
  end |> lists -> join(lists, "\n")

  push!(docstrings, Dict(:type  => :markdown,
                         :value => header * body))
end

function makedatatip(docstring, word, mtable)
  # @NOTE: Separates non code blocks that would be rendered as markdown text (horrible hack)
  texts = split(string(docstring), r"```[^```]+```")
  codes = searchcodeblocks(docstring)

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
  docstring = @errs getdocs(mod, word)

  docstring isa EvalError && return Dict(:error => true)

  mtable = try getmethods(mod, word) catch e [] end

  mdstring = string(docstring)
  Dict(:error    => false,
       :strings  => makedatatip(docstring, word, mtable))
end
