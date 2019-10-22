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

  # check on dot accessor
  moddesc = if (obj = first(split(full, '.'))) != old
    if (parentmod = getfield′(mod, obj)) isa Module
      if parentmod != mod
        moduledescription(old, parentmod)
      else
        ""
      end
    else
      # catch field renaming
      return Dict(:warning => "Rename refactoring on a field isn't available: `$obj.$old`")
    end
  else
    ""
  end

  expr = CSTParser.parse(context)
  bind = CSTParser.bindingof(expr)

  # local rename refactor if `old` isn't a toplevel binding
  if bind === nothing || old ≠ bind.name
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

  # global rename refactor if the local rename refactor didn't happen
  try
    val = getfield′(mod, full)

    # catch keyword renaming
    if val isa Undefined && Symbol(old) in keys(Docs.keywords)
      return Dict(:warning => "Keywords can't be renamed: `$old`")
    end

    # catch global refactoring not on definition, e.g.: on a call site
    if bind === nothing || old ≠ bind.name
      # TODO: `goto` uri
      return Dict(:info => contextdescription(old, mod, context))
    end

    kind, desc = globalrefactor(old, new, mod, expr)

    # make description
    if kind === :success
      # update modesc
      if isempty(moddesc) && applicable(parentmodule, val) && (parentmod = parentmodule(val)) ≠ mod
        moddesc = moduledescription(old, parentmod)
      end

      desc = join(("_Global_ rename refactoring `$old` ⟹ `$new` succeeded.", moddesc, desc), "\n\n")
    end

    return Dict(kind => desc)
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

function globalrefactor(old, new, mod, expr)
  entrypath, line = moduledefinition(mod)
  files = modulefiles(entrypath)

  with_logger(JunoProgressLogger()) do
    refactorfiles(old, new, mod, files, expr)
  end
end

function refactorfiles(old, new, mod, files, expr)
  ismacro = CSTParser.defines_macro(expr)
  oldsym = ismacro ? Symbol("@" * old) : Symbol(old)
  newsym = ismacro ? Symbol("@" * new) : Symbol(new)

  total  = length(files)
  # TODO: enable line location information (the upstream needs to be enhanced)
  refactoredfiles = Set{String}()

  id = "global_rename_refactor_progress"
  @info "Start global rename refactoring" progress=0 _id=id

  for (i, file) ∈ enumerate(files)
    @info "Refactoring: $file ($i / $total)" progress=i/total _id=id

    MacroTools.sourcewalk(file) do ex
      if ex === oldsym
        push!(refactoredfiles, fullpath(file))
        newsym
      # handle dot (module) accessor
      elseif @capture(ex, m_.$oldsym) && getfield′(mod, Symbol(m)) isa Module
        push!(refactoredfiles, fullpath(file))
        Expr(:., m, newsym)
      # macro case
      elseif ismacro && @capture(ex, macro $(Symbol(old))(args__) body_ end)
        push!(refactoredfiles, fullpath(file))
        Expr(:macro, :($(Symbol(new))($(args...))), :($body))
      else
        ex
      end
    end
  end

  @info "Finish global rename refactoring" progress=1 _id=id

  return if !isempty(refactoredfiles)
    (:success, filedescription(mod, refactoredfiles))
  else
    (:warning, "No rename refactoring occured on `$old` in `$mod` module.")
  end
end

# descriptions
# ------------

moduledescription(old, parentmod) = """
  **NOTE**: `$old` is defined in `$parentmod`
  -- you may need the same rename refactorings in that module as well.
  """

contextdescription(old, mod, context) = """
  `$old` isn't found in local bindings in the current context:
  <details><summary>Context</summary><pre><code>$(strip(context))</code></p></details>

  If you want a global rename refactoring on `$mod.$old`, you need to call from its definition.
  """

function filedescription(mod, files)
  filelist = join(("<li>[$file]($(uriopen(file)))</li>" for file in files), '\n')
  """
  <details><summary>
  Refactored files (all in `$mod` module):
  </summary><ul>$(filelist)</ul></details>
  """
end
