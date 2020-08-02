using JuliaFormatter

handle("format") do data
  @destruct [
    text,
    dir || ".",
    indent || 4,
    margin || 92,
  ] = data

  options = if (config_path = search_up_file(JuliaFormatter.CONFIG_FILE_NAME, dir)) === nothing
    JuliaFormatter.kwargs((indent = indent, margin = margin)) # fallback
  else
    JuliaFormatter.kwargs(JuliaFormatter.parse_config(config_path))
  end

  try
    return (formattedtext = format_text′(text; options...),)
  catch err
    if err isa ErrorException && startswith(err.msg, "Parsing error")
      return (error = """
      Juno's formatter expects a text that can be parsed into a valid Julia expression.
      The given text below couldn't be parsed correctly:
      ```
      $(replace(strip(text), "```" => "\`\`\`"))
      ```
      """,)
    end
    return (error = """\n$(string(err))\n""",)
  end
end

# HACK: extract keyword arguments of `format_text`; `Base.kwarg_decl` isn't available as of v1.0
const FORMAT_TEXT_KWARGS = try
  s = filter!(collect(methods(format_text))) do m
    return m.module == JuliaFormatter &&
      length(m.sig.types) === 2
  end |> first |> string
  m = match(r";(.+)\)", s)
  m === nothing ? Symbol[] : Symbol.(strip.(split(m.captures[1]), Ref((' ', ','))))
catch
  Symbol[]
end

isempty(FORMAT_TEXT_KWARGS) && @warn """
Atom.jl failed to recognize the keyword arguments of `JuliaFormatter.format_text`.
The formatting options won't work when you format code via Juno's formatting interface.
"""

function format_text′(text; options...)
  # only pass valid keyword arguments to `format_text`
  valid_option_dict = filter(options) do (k, _)
    @static isempty(FORMAT_TEXT_KWARGS) ? false : in(k,FORMAT_TEXT_KWARGS)
  end
  return format_text(text; JuliaFormatter.kwargs(valid_option_dict)...)
end
