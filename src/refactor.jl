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
  modnote = if (obj = first(split(full, '.'))) != old
    if (parentmod = getfield′(mod, obj)) isa Module && parentmod != mod
      modulenote(old, parentmod)
    else
      return Dict(:warning => "Rename refactoring on a field isn't available: `$obj.$old`")
    end
  else
    ""
  end

  # local refactor only if `old` is really a local binding
  bind = CSTParser.bindingof(CSTParser.parse(context))
  if bind === nothing || old != bind.name
    try
      refactored = localrefactor(old, new, path, column, row, startrow, context)
      isempty(refactored) || return Dict(
        :text    => refactored,
        :success => "_Local_ rename refactoring `$old` ⟹ `$new` succeeded"
      )
    catch err
      @error err
    end
  end

  try
    val = getfield′(mod, full)
    # catch keyword renaming
    if val isa Undefined && Symbol(old) in keys(Docs.keywords)
      return Dict(:warning => "Keywords can't be renamed: `$old`")
    end
    # update modnote
    if isempty(modnote) && applicable(parentmodule, val) && (parentmod = parentmodule(val)) != mod
      modnote = modulenote(old, parentmod)
    end
    kind, desc = globalrefactor(old, new, mod)
    return Dict(
      kind => kind === :success ?
        join(("_Global_ rename refactoring `$old` ⟹ `$new` succeeded.", modnote, desc), "\n\n") :
        desc
    )
  catch err
    @error err
  end

  return Dict(:error => "Rename refactoring `$old` ⟹ `$new` failed")
end

modulenote(old, parentmod) =
  "**NOTE**: `$old` is defined in `$parentmod` -- you may need the same rename refactorings in that module as well."

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

function globalrefactor(old, new, mod)
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

  # TODO: enable line location information (the upstream needs to be enhanced)
  refactoredfiles = Set{String}()

  for (i, file) ∈ enumerate(files)
    @info "Refactoring: $file ($i / $total)" progress=i/total _id=id
    MacroTools.sourcewalk(file) do ex
      return if ex === oldsym
        push!(refactoredfiles, fullpath(file))
        newsym
      elseif @capture(ex, m_.$oldsym) && getfield′(mod, Symbol(m)) isa Module
        push!(refactoredfiles, fullpath(file))
        Expr(:., m, newsym)
      else
        ex
      end
    end
  end

  @info "Finish global rename refactoring" progress=1 _id=id

  return if !isempty(refactoredfiles)
    filelist = ("- [$file]($(uriopen(file)))" for file in refactoredfiles)
    (:success, string("Refactored files (all in `$mod` module):\n\n", join(filelist, '\n')))
  else
    (:warning, "No rename refactoring occured on `$old` in `$mod` module.")
  end
end
