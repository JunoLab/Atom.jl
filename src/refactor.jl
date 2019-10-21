handle("renamerefactor") do data
  @destruct [
    old,
    full,
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
  renamerefactor(old, full, new, path, column, row, startRow, context, mod)
end

function renamerefactor(
  old, full, new, path,
  column = 1, row = 1, startrow = 0, context = "",
  mod = "Main",
)
  mod = getmodule(mod)

  # catch field renaming
  if (obj = first(split(full, '.'))) != old && !isa(getfield′(mod, obj), Module)
    return Dict(:warning => "Rename refactoring on a field isn't available: `$obj.$old`")
  end

  # local refactor only if `old` is really a local binding
  bind = CSTParser.bindingof(CSTParser.parse(context))
  if bind === nothing || old != bind.name
    try
      refactored = localrefactor(old, new, path, column, row, startrow, context)
      isempty(refactored) || return Dict(
        :text    => refactored,
        :success => "Local rename refactoring `$old` ⟹ `$new` succeeded"
      )
    catch err
      @error err
    end
  end

  try
    val = getfield′(mod, old)
    kind, description = globalrefactor(old, new, mod, val)
    return Dict(
      kind     => description,
      :success => kind !== :info ? false :
        "Global rename refactoring `$old` ⟹ `$new` succeeded"
    )
  catch err
    @error err
  end

  return Dict(:error => "Rename refactoring `$old` ⟹ `$new` failed")
end

# local refactor
# --------------

function localrefactor(old, new, path, column, row, startrow, context)
  return if old ∈ map(l -> l[:name], locals(context, row - startrow, column))
    oldsym = Symbol(old)
    newsym = Symbol(new)
    MacroTools.textwalk(context) do sym
      sym === oldsym ? newsym : sym
    end
  else
    ""
  end
end

# global refactor
# ---------------

globalrefactor(old, new, mod, @nospecialize(val)) = _globalrefactor(old, new, mod) # general case
function globalrefactor(old, new, mod, val::Undefined)
  Symbol(old) in keys(Docs.keywords) ?
    (:warning, "Keywords can't be renamed: `$old`") :
    _globalrefactor(old, new, mod)
end

function _globalrefactor(old, new, mod)
  entrypath, line = moduledefinition(mod)
  files = modulefiles(entrypath)

  with_logger(JunoProgressLogger()) do
    refactorfiles(old, new, mod, files)
  end
end

function refactorfiles(old, new, mod, files)
  id = "global_rename_refactor_progress"
  @info "Start global rename refactoring" progress=0 _id=id

  oldsym = Symbol(old)
  newsym = Symbol(new)
  total  = length(files)
  desc = ""

  for (i, file) ∈ enumerate(files)
    @info "Refactoring: $file ($i / $total)" progress=i/total _id=id
    MacroTools.sourcewalk(file) do ex
      return if ex === oldsym
        newsym
      elseif @capture(ex, m_.$oldsym) && getfield′(mod, Symbol(m)) isa Module
        # TODO: enable line location information (the upstream needs to be enhanced)
        file = fullpath(file)
        link = "atom://julia-client/?open=true&file=$(file)&line=0"
        desc *= "- `$m.$old` ⟹ `$m.$new` in [$file]($link)\n"
        Expr(:., m, newsym)
      else
        ex
      end
    end
  end

  @info "Finish global rename refactoring" progress=1 _id=id

  (:info, isempty(desc) ? "" : "Refactorings across modules\n" * desc)
end
