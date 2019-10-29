handle("renamerefactor") do data
  @destruct [
    old,
    full,
    new,
    # local context
    column || 1,
    row || 1,
    startRow || 0,
    context || "",
    # module context
    mod || "Main",
  ] = data
  renamerefactor(old, full, new, column, row, startRow, context, mod)
end

# NOTE: invalid identifiers will be caught by frontend
function renamerefactor(
  old, full, new,
  column = 1, row = 1, startrow = 0, context = "",
  mod = "Main",
)
  # catch keyword renaming
  iskeyword(old) && return Dict(:warning => "Keywords can't be renamed: `$old`")

  mod = getmodule(mod)
  hstr = first(split(full, '.'))
  head = getfield′(mod, hstr)

  # catch field renaming
  hstr ≠ old && !isa(head, Module) && return Dict(
    :warning => "Rename refactoring on a field isn't available: `$hstr.$old`"
  )

  expr = CSTParser.parse(context)
  bind = let
    if expr !== nothing
      items = toplevelitems(expr, context)
      ind = findfirst(item -> item isa ToplevelBinding, items)
      ind === nothing ? nothing : items[ind].bind
    else
      nothing
    end
  end

  # local rename refactor if `old` isn't a toplevel binding
  if islocalrefactor(bind, old)
    try
      refactored = localrenamerefactor(old, new, column, row, startrow, context, expr)
      return isempty(refactored) ?
        # NOTE: global refactoring not on definition, e.g.: on a call site, will be caught here
        Dict(:info => contextdescription(old, mod, context)) :
        Dict(
          :text    => refactored,
          :success => "_Local_ rename refactoring `$old` ⟹ `$new` succeeded"
        )
    catch err
      return Dict(:error => errdescription(old, new, err))
    end
  end

  # global rename refactor if the local rename refactor didn't happen
  try
    kind, desc = globalrenamerefactor(old, new, mod, expr)

    # make description
    if kind === :success
      val = getfield′(mod, full)
      moddesc = if (head isa Module && head ≠ mod) ||
                   (applicable(parentmodule, val) && (head = parentmodule(val)) ≠ mod)
        moduledescription(old, head)
      else
        ""
      end

      desc = join(("_Global_ rename refactoring `$mod.$old` ⟹ `$mod.$new` succeeded.", moddesc, desc), "\n\n")
    end

    return Dict(kind => desc)
  catch err
    return Dict(:error => errdescription(old, new, err))
  end
end

islocalrefactor(bind, name) = bind === nothing || name ≠ bind.name

# local refactor
# --------------

function localrenamerefactor(old, new, column, row, startrow, context, expr)
  bindings = localbindings(expr, context)
  line = row - startrow
  scope = currentscope(old, bindings, byteoffset(context, line, column))
  scope === nothing && return ""

  currentcontext = scope.bindstr
  oldsym = Symbol(old)
  newsym = Symbol(new)
  newcontext = MacroTools.textwalk(currentcontext) do sym
    sym === oldsym ? newsym : sym
  end

  replace(context, currentcontext => newcontext)
end
localrenamerefactor(old, new, column, row, startrow, context, expr::Nothing) = ""

function currentscope(name, bindings, byteoffset)
  for binding in bindings
    isa(binding, LocalScope) || continue

    # first looks for innermost scope
    childscope = currentscope(name, binding.children, byteoffset)
    childscope !== nothing && return childscope

    if byteoffset in binding.span &&
       any(bind -> bind isa LocalBinding && name == bind.name, binding.children)
      return binding
    end
  end

  return nothing
end

# global refactor
# ---------------

function globalrenamerefactor(old, new, mod, expr)
  entrypath, _ = if mod == Main
    MAIN_MODULE_LOCATION[]
  else
    moduledefinition(mod)
  end

  files = modulefiles(entrypath)

  # catch refactorings on an unsaved / non-existing file
  isempty(files) && return :warning, unsaveddescription()

  # catch refactorings on files without write permission
  nonwritables = nonwritablefiles(files)
  if !isempty(nonwritables)
    return :warning, nonwritablesdescription(mod, nonwritables)
  end

  with_logger(JunoProgressLogger()) do
    _globalrenamerefactor(old, new, mod, expr, files)
  end
end

function _globalrenamerefactor(old, new, mod, expr, files)
  ismacro = CSTParser.defines_macro(expr)
  oldsym = ismacro ? Symbol("@" * old) : Symbol(old)
  newsym = ismacro ? Symbol("@" * new) : Symbol(new)

  total  = length(files)
  # TODO: enable line location information (the upstream needs to be enhanced)
  modifiedfiles = Set{String}()

  id = "global_rename_refactor_progress"
  @info "Start global rename refactoring" progress=0 _id=id

  for (i, file) ∈ enumerate(files)
    @logmsg -1 "Refactoring: $file ($i / $total)" progress=i/total _id=id

    MacroTools.sourcewalk(file) do ex
      if ex === oldsym
        push!(modifiedfiles, fullpath(file))
        newsym
      # handle dot accessor
      elseif @capture(ex, m_.$oldsym) && getfield′(mod, Symbol(m)) isa Module
        push!(modifiedfiles, fullpath(file))
        Expr(:., m, newsym)
      # macro case
      elseif ismacro && @capture(ex, macro $(Symbol(old))(args__) body_ end)
        push!(modifiedfiles, fullpath(file))
        Expr(:macro, :($(Symbol(new))($(args...))), :($body))
      else
        ex
      end
    end
  end

  @info "Finish global rename refactoring" progress=1 _id=id

  return if !isempty(modifiedfiles)
    :success, filesdescription(mod, modifiedfiles)
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
  <details><summary>Context:</summary><pre><code>$(strip(context))</code></p></details>

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

function unsaveddescription()
  """
  Global rename refactor failed, since the given file isn't saved on the disk yet.
  Please run this command again after you save the file.
  """
end

function nonwritablesdescription(mod, files)
  filelist = join(("<li>[$file]($(uriopen(file)))</li>" for file in files), '\n')
  """
  Global rename refactor failed, since there are non-writable files detected in
  `$mod` module. Please make sure the files have an write access.

  <details><summary>
  Non writable files (all in `$mod` module):
  </summary><ul>$(filelist)</ul></details>
  """
end

function filesdescription(mod, files)
  filelist = join(("<li>[$file]($(uriopen(file)))</li>" for file in files), '\n')
  """
  <details><summary>
  Refactored files (all in `$mod` module):
  </summary><ul>$(filelist)</ul></details>
  """
end

function errdescription(old, new, err)
  """
  Rename refactoring `$old` ⟹ `$new` failed.

  <details><summary>Error:</summary><pre><code>$(errmsg(err))</code></p></details>
  """
end
