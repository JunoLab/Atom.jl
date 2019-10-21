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
  # local refactor only if `old` is really a local binding
  bind = CSTParser.bindingof(CSTParser.parse(context))
  if bind === nothing || old != bind.name
    try
      refactored = localrefactor(old, new, path, column, row, startrow, context)
      isempty(refactored) || return Dict(:text => refactored)
    catch err
      @error err
    end
  end

  try
    mod = getmodule(mod)
    val = getfield′(mod, old)
    result = globalrefactor(old, new, mod, val)
    return result isa String ? Dict(:error => result) : Dict(:error => false)
  catch err
    @error err
  end

  return Dict(:error => "Rename refactoring failed: `$old` -> `$new`")
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
    "Keywords can't be renamed: `$old`" :
    _globalrefactor(old, new, mod)
end

function _globalrefactor(old, new, mod)
  entrypath, line = moduledefinition(mod)
  files = modulefiles(entrypath)

  with_logger(JunoProgressLogger()) do
    refactorfiles(old, new, mod, files)
  end
end

function refactorfiles(old, new, obj, files)
  id = "global_rename_refactor_progress"
  @info "Start global rename refactoring" progress=0 _id=id

  oldsym     = Symbol(old)
  newsym     = Symbol(new)
  modulesyms = Set(Symbol.(Base.loaded_modules_array()))
  total      = length(files)

  for (i, file) ∈ enumerate(files)
    @info "Refactoring: $file ($i / $total)" progress=i/total _id=id
    MacroTools.sourcewalk(file) do ex
      return if ex === oldsym
        newsym
      elseif @capture(ex, obj_.$oldsym)
        if obj in modulesyms
          @warn "Came across a global rename refactoring across different modules: `$obj.$old` -> `$obj.$new`"
        end
        Expr(:., obj, newsym)
      else
        ex
      end
    end
  end

  @info "Finish global rename refactoring" progress=1 _id=id
end
