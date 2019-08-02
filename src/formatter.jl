using JuliaFormatter: format_text

handle("format") do data
  @destruct [text, indent || 4, margin || 92] = data

  formattedtext = format_text(text, indent = indent, margin = margin)
  Dict(:formattedtext => formattedtext)
end
