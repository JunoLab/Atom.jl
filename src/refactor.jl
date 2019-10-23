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
  # catch keyword renaming
  iskeyword(old) && return Dict(:warning => "Keywords can't be renamed: `$old`")

  mod = getmodule(mod)
  head = first(split(full, '.'))
  headval = getfield′(mod, head)

  # catch field renaming
  head ≠ old && !isa(headval, Module) && return Dict(
    :warning => "Rename refactoring on a field isn't available: `$obj.$old`"
  )

  expr = CSTParser.parse(context)
  items = toplevelitems(expr, context)
  ind = findfirst(item -> item isa ToplevelBinding, items)
  bind = ind === nothing ? nothing : items[ind].bind

  # local rename refactor if `old` isn't a toplevel binding
  if islocalrefactor(bind, old)
    try
      refactored = localrefactor(old, new, path, column, row, startrow, context, expr)
      return isempty(refactored) ?
        # NOTE: global refactoring not on definition, e.g.: on a call site, will be caught here
        Dict(:info => contextdescription(old, mod, context)) :
        Dict(
          :text    => refactored,
          :success => "_Local_ rename refactoring `$old` ⟹ `$new` succeeded"
        )
    catch err
      @error err
    end
  end

  # global rename refactor if the local rename refactor didn't happen
  try
    kind, desc = globalrefactor(old, new, mod, expr)

    # make description
    if kind === :success
      val = getfield′(mod, full)
      moddesc = if (headval isa Module && headval ≠ mod) ||
                   (applicable(parentmodule, val) && (headval = parentmodule(val)) ≠ mod)
        moduledescription(old, headval)
      else
        ""
      end

      desc = join(("_Global_ rename refactoring `$mod.$old` ⟹ `$mod.$new` succeeded.", moddesc, desc), "\n\n")
    end

    return Dict(kind => desc)
  catch err
    @error err
  end

  return Dict(:error => "Rename refactoring `$old` ⟹ `$new` failed")
end

islocalrefactor(bind, name) = bind === nothing || name ≠ bind.name

# local refactor
# --------------

function localrefactor(old, new, path, column, row, startrow, context, expr)
  bindings = local_bindings(expr, context)
  line = row - startrow
  scope = current_scope(old, bindings, byteoffset(context, line, column))
  scope === nothing && return ""

  current_context = scope.bindstr
  oldsym = Symbol(old)
  newsym = Symbol(new)
  new_context = MacroTools.textwalk(current_context) do sym
    sym === oldsym ? newsym : sym
  end

  replace(context, current_context => new_context)
end

function current_scope(name, bindings, byteoffset)
  for binding in bindings
    isa(binding, LocalScope) || continue

    scope = binding
    if byteoffset in scope.span &&
       any(bind -> bind isa LocalBinding && name == bind.name, scope.children)
      return scope
    else
      let scope = current_scope(name, scope.children, byteoffset)
        scope !== nothing && return scope
      end
    end
  end

  return nothing
end

# global refactor
# ---------------

function globalrefactor(old, new, mod, expr)
  entrypath, line = if mod == Main
    MAIN_MODULE_LOCATION[]
  else
    moduledefinition(mod)
  end
  files = modulefiles(entrypath)

  nonwritablefiles = filter(f -> Int(Base.uperm(f)) ≠ 6, files)
  if !isempty(nonwritablefiles)
    return :warning, nonwritabledescription(mod, nonwritablefiles)
  end

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
    :success, filedescription(mod, refactoredfiles)
  else
    :warning, "No rename refactoring occured on `$old` in `$mod` module."
  end
end

# descriptions
# ------------

function contextdescription(old, mod, context)
  gotouri = urigoto(mod, old)
  """
  `$old` isn't found in local bindings in the current context:
  <details><summary>Context</summary><pre><code>$(strip(context))</code></p></details>

  If you want a global rename refactoring on `$mod.$old`, you need to run this command
  from its definition. <button>[Go to `$mod.$old`]($gotouri)</button>
  """
end

function moduledescription(old, parentmod)
  gotouri = urigoto(parentmod, old)
  """
  **NOTE**: `$old` is defined in `$parentmod` -- you may need the same rename refactorings
  in that module as well. <button>[Go to `$parentmod.$old`]($gotouri)</button>
  """
end

function nonwritabledescription(mod, files)
  filelist = join(("<li>[$file]($(uriopen(file)))</li>" for file in files), '\n')
  """
  Global rename refactor failed, since there are non-writable files detected in
  `$mod` module.

  <details><summary>
  Non writable files (all in `$mod` module):
  </summary><ul>$(filelist)</ul></details>
  """
end

function filedescription(mod, files)
  filelist = join(("<li>[$file]($(uriopen(file)))</li>" for file in files), '\n')
  """
  <details><summary>
  Refactored files (all in `$mod` module):
  </summary><ul>$(filelist)</ul></details>
  """
end
