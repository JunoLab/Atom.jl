using JuliaFormatter: format_text

handle("format") do data
  @destruct [
    text,
    indent || 4,
    margin || 92,
    always_for_in || false,
    whitespace_typedefs || false,
    whitespace_ops_in_indices || false,
    remove_extra_newlines || false
  ] = data

  return Dict(:formattedtext => format_text(
    text;
    indent = indent,
    margin = margin,
    always_for_in = always_for_in,
    whitespace_typedefs = whitespace_typedefs,
    whitespace_ops_in_indices = whitespace_ops_in_indices,
    remove_extra_newlines = remove_extra_newlines
  ))
end
