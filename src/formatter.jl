using DocumentFormat: format

handle("format") do data
  @destruct [text, indent || nothing] = data

  # @TODO: `indent` is here since we can pass it to `format` function once
  #        DocumentFormat.jl comes to be able to handle options to specify indents,
  formattedtext = format(text)
  d(:formattedtext => formattedtext)
end
