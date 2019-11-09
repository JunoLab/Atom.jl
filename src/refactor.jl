using SourceWalk: textwalk, sourcewalk

handle("renamerefactor") do data
  @destruct [
    oldWord,
    fullWord,
    newWord,
    # local context
    column || 1,
    row || 1,
    startRow || 0,
    context || "",
    # module context
    mod || "Main",
  ] = data
  renamerefactor(oldWord, fullWord, newWord, column, row, startRow, context, mod)
end

# NOTE: invalid identifiers will be caught by frontend
function renamerefactor(
  oldword, fullword, newword,
  column = 1, row = 1, startrow = 0, context = "",
  mod = "Main",
)
  # catch keyword renaming
  iskeyword(oldword) && return Dict(:warning => "Keywords can't be renamed: `$oldword`")

  mod = getmodule(mod)
  hstr = first(split(fullword, '.'))
  head = getfield′(mod, hstr)

  # catch field renaming
  hstr ≠ oldword && !isa(head, Module) && return Dict(
    :warning => "Rename refactoring on a field isn't available: `$hstr.$oldword`"
  )

  expr = CSTParser.parse(context)

  bind = let
    items = toplevelitems(context, expr)
    ind = findfirst(item -> item isa ToplevelBinding, items)
    ind === nothing ? nothing : items[ind].bind
  end

  # local rename refactor if `old` isn't a toplevel binding
  if islocalrefactor(bind, oldword)
    try
      refactored = localrenamerefactor(oldword, newword, column, row, startrow, context, expr)
      return isempty(refactored) ?
        # NOTE: global refactoring not on definition, e.g.: on a call site, will be caught here
        Dict(:info => contextdescription(oldword, mod, context)) :
        Dict(
          :text    => refactored,
          :success => "_Local_ rename refactoring `$oldword` ⟹ `$newword` succeeded"
        )
    catch err
      return Dict(:error => errdescription(oldword, newword, err))
    end
  end

  # global rename refactor if the local rename refactor didn't happen
  try
    kind, desc = globalrenamerefactor(oldword, newword, mod, expr)

    # make description
    if kind === :success
      val = getfield′(mod, fullword)
      moddesc = if (head isa Module && head ≠ mod) ||
                   (applicable(parentmodule, val) && (head = parentmodule(val)) ≠ mod)
        moduledescription(oldword, head)
      else
        ""
      end

      desc = join(("_Global_ rename refactoring `$mod.$oldword` ⟹ `$mod.$newword` succeeded.", moddesc, desc), "\n\n")
    end

    return Dict(kind => desc)
  catch err
    return Dict(:error => errdescription(oldword, newword, err))
  end
end

islocalrefactor(bind, name) = bind === nothing || name ≠ bind.name

# local refactor
# --------------

function localrenamerefactor(oldword, newword, column, row, startrow, context, expr)
  bindings = localbindings(expr, context)
  line = row - startrow
  scope = currentscope(oldword, bindings, byteoffset(context, line, column))
  scope === nothing && return ""

  currentcontext = scope.bindstr
  oldsym = Symbol(oldword)
  newsym = Symbol(newword)
  newcontext = textwalk(currentcontext) do sym
    sym === oldsym ? newsym : sym
  end

  replace(context, currentcontext => newcontext)
end
localrenamerefactor(oldword, newword, column, row, startrow, context, expr::Nothing) = ""

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

function globalrenamerefactor(oldword, newword, mod, expr)
  entrypath, _ = if mod == Main
    MAIN_MODULE_LOCATION[]
  else
    moduledefinition(mod)
  end

  files = modulefiles(string(mod), entrypath)

  # catch refactorings on an unsaved / non-existing file
  isempty(files) && return :warning, unsaveddescription()

  # catch refactorings on files without write permission
  nonwritables = nonwritablefiles(files)
  if !isempty(nonwritables)
    return :warning, nonwritablesdescription(mod, nonwritables)
  end

  with_logger(JunoProgressLogger()) do
    _globalrenamerefactor(oldword, newword, mod, expr, files)
  end
end

function _globalrenamerefactor(oldword, newword, mod, expr, files)
  ismacro = CSTParser.defines_macro(expr)
  oldsym = ismacro ? Symbol("@" * oldword) : Symbol(oldword)
  newsym = ismacro ? Symbol("@" * newword) : Symbol(newword)

  total  = length(files)
  # TODO: enable line location information (the upstream needs to be enhanced)
  modifiedfiles = Set{String}()

  id = "global_rename_refactor_progress"
  @info "Start global rename refactoring" progress=0 _id=id

  for (i, file) ∈ enumerate(files)
    @logmsg -1 "Refactoring: $file ($i / $total)" progress=i/total _id=id

    sourcewalk(file) do ex
      if ex === oldsym
        push!(modifiedfiles, fullpath(file))
        newsym
      # handle dot accessor
      elseif @capture(ex, m_.$oldsym) && getfield′(mod, Symbol(m)) isa Module
        push!(modifiedfiles, fullpath(file))
        Expr(:., m, newsym)
      # macro case
      elseif ismacro && @capture(ex, macro $(Symbol(oldword))(args__) body_ end)
        push!(modifiedfiles, fullpath(file))
        Expr(:macro, :($(Symbol(newword))($(args...))), :($body))
      else
        ex
      end
    end
  end

  @info "Finish global rename refactoring" progress=1 _id=id

  return if !isempty(modifiedfiles)
    :success, filesdescription(mod, modifiedfiles)
  else
    :warning, "No rename refactoring occured on `$oldword` in `$mod` module."
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

function errdescription(oldword, newword, err)
  """
  Rename refactoring `$oldword` ⟹ `$newword` failed.

  <details><summary>Error:</summary><pre><code>$(errmsg(err))</code></p></details>
  """
end
