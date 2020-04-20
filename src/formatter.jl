using JuliaFormatter

@static if isdefined(JuliaFormatter, :CONFIG_FILE_NAME) &&
           isdefined(JuliaFormatter, :kwargs) &&
           isdefined(JuliaFormatter, :parse_config) &&
           isdefined(JuliaFormatter, :overwrite_options)
  using JuliaFormatter: CONFIG_FILE_NAME, kwargs, parse_config, overwrite_options
else
  const CONFIG_FILE_NAME = ".JuliaFormatter.toml"

  function kwargs(dict)
      ns = (Symbol.(keys(dict))...,)
      vs = (collect(values(dict))...,)
      return pairs(NamedTuple{ns}(vs))
  end

  function parse_config(tomlfile)
    config_dict = Pkg.TOML.parsefile(tomlfile)
    if (style = get(config_dict, "style", nothing)) !== nothing
      @assert (style == "default" || style == "yas") "currently $(CONFIG_FILE_NAME) accepts only \"default\" or \"yas\" for the style configuration"
      if style == "yas" && isdefined(JuliaFormatter, :YASStyle)
        config_dict["style"] = JuliaFormatter.YASStyle()
      end
    end
    return kwargs(config_dict)
  end

  overwrite_options(options, config) = kwargs(merge(options, config))
end

handle("format") do data
  @destruct [
    text,
    dir,
    indent || 4,
    margin || 92,
  ] = data

  options = if (config_path = search_up_file(CONFIG_FILE_NAME, dir)) === nothing
    kwargs((indent = indent, margin = margin)) # fallback
  else
    kwargs(parse_config(config_path))
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
const FORMAT_TEXT_KWARGS = let
  ms = collect(methods(format_text))
  filter!(m->m.module==JuliaFormatter, ms)
  m = match(r";(.+)\)", string(first(ms)))
  m === nothing ? Symbol[] : Symbol.(strip.(split(m.captures[1]), Ref((' ', ','))))
end
function format_text′(text; options...)
  # only pass valid keyword arguments to `format_text`
  valid_option_dict = filter(options) do (k, _)
    @static isempty(FORMAT_TEXT_KWARGS) ? false : in(k,FORMAT_TEXT_KWARGS)
  end
  return format_text(text; kwargs(valid_option_dict)...)
end
