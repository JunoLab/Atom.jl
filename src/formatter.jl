using JuliaFormatter

handle("format") do data
  @destruct [
    text,
    indent || 4,
    margin || 92,
    always_for_in || false,
    whitespace_typedefs || false,
    whitespace_ops_in_indices || false,
    remove_extra_newlines || false,
    import_to_using || false,
    pipe_to_function_call || false,
    short_to_long_function_def || false,
    always_use_return || false,
    use_YAS_style || false
  ] = data

  style = (use_YAS_style && isdefined(JuliaFormatter, :YASStyle)) ?
    JuliaFormatter.YASStyle() :
    JuliaFormatter.DefaultStyle()

  return Dict(:formattedtext => format_text′(
    text;
    indent = indent,
    margin = margin,
    always_for_in = always_for_in,
    whitespace_typedefs = whitespace_typedefs,
    whitespace_ops_in_indices = whitespace_ops_in_indices,
    remove_extra_newlines = remove_extra_newlines,
    import_to_using = import_to_using,
    pipe_to_function_call = pipe_to_function_call,
    short_to_long_function_def = short_to_long_function_def,
    always_use_return = always_use_return,
    style = style
  ))
end

# HACK: extract keyword arguments of `format_text`; `Base.kwarg_decl` isn't available as of v1.0
const FORMAT_TEXT_KWARGS = let
  ms = collect(methods(format_text))
  filter!(m->m.module==JuliaFormatter, ms)
  m = match(r";(.+)\)", string(first(ms)))
  m === nothing ? Symbol[] : Symbol.(strip.(split(m.captures[1]), Ref((' ', ','))))
end
function format_text′(text; kwargs...)
  # only pass valid keyword arguments to `format_text`
  valid_kwargs_dict = filter(kwargs) do (k, _)
    @static isempty(FORMAT_TEXT_KWARGS) ? false : in(k,FORMAT_TEXT_KWARGS)
  end
  ks = (collect(keys(valid_kwargs_dict))...,)
  vs = (collect(values(valid_kwargs_dict))...,)
  valid_kwargs_nt = NamedTuple{ks}(vs)
  valid_kwargs = pairs(valid_kwargs_nt)

  format_text(text; valid_kwargs...)
end
