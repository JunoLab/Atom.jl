handle("refactor") do data
  @destruct [
    old,
    new,
    path,
    # local context
    column || 1,
    row || 1,
    startRow || 0,
    context || "",
    # module context
    mod || "Main",
  ] = data
  refactor(old, new, path, column, row, startRow, context, mod)
end

function refactor(
  old, new, path,
  column = 1, row = 1, startrow = 0, context = "",
  mod = "Main",
)
  expr = CSTParser.parse(context, true)
  bind = CSTParser.bindingof(expr)

  # local refactor only if `old` is really a local binding
  if bind === nothing || old != bind.name
    try
      refactored = localrefactor(old, new, path, column, row, startrow, context)
      isempty(refactored) || return Dict(:text => refactored)
    catch err
      @error err
    end
  end

  try
    refactored = localrefactor(old, new, path, column, row, startrow, context)
    isempty(refactored) || return Dict(:text => refactored)
  catch err
    @error err
  end

  # try
  #   globalrefactor(old, new, path, mod) && return nothing
  # catch err
  #   @error err
  # end

  return Dict(:error => true, :msg => "no refactor")
end

function localrefactor(old, new, path, column, row, startrow, context)
  old = first(split(old, '.')) # ignore dot accessors
  position = row - startrow

  return if old ∈ map(l -> l[:name], locals(context, position, column))
    oldsym = Symbol(old)
    quote
      MacroTools.textwalk($context) do ex
        @capture(ex, $oldsym) ? Symbol($new) : ex
      end
    end |> eval
  else
    ""
  end
end

# mod = getmodule(m)
# parentfile, modulefiles = modulefiles(mod)
# sourcewalk("../packages/Atom/src/goto.jl") do x
#   isshort = MacroTools.isshortdef(x)
#   ex = MacroTools.shortdef(x)
#   if @capture(ex, locals(args__) = body_)
#     return if isshort
#       :(newlocals(args...) = body)
#     else
#       :(function newlocals(args...)
#         body
#       end)
#     end
#   end
#   return x
#   isstruct = MacroTools.isstructdef(x)
#   if @capture(x, struct )
# end
