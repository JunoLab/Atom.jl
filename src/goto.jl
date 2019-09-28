handle("goto") do data
  @destruct [
    word,
    path || "",
    mod || "Main",
    column || 1,
    row || 1,
    startRow || 0,
    context || "",
    onlytoplevel || false
  ] = data
  goto(word, mod, path, column, row, startRow, context, onlytoplevel)
end

function goto(word, mod, path, column = 1, row = 1, startRow = 0, context = "", onlytoplevel = false)
  mod = getmodule(mod)

  # local items
  if !onlytoplevel
    localitems = localgotoitem(word, path, column, row, startRow, context)
    isempty(localitems) || return Dict(:error => false, :items => localitems)
  end

  # toplevel items
  toplevelitems = toplevelgotoitem(mod, word)
  isempty(toplevelitems) || return Dict(:error => false, :items => toplevelitems)

  # method goto
  methodgotoitems = methodgotoitem(mod, word)
  isempty(methodgotoitems) || return Dict(:error => false, :items => methodgotoitems)

  Dict(:error => true) # nothing hits
end

function localgotoitem(word, path, column, row, startRow, context)
  position = row - startRow
  ls = locals(context, position, column)
  filter!(ls) do l
    l[:name] == word &&
    l[:line] < position
  end
  map(ls) do l # there should be zero or one element in `ls`
    text = l[:name]
    line = startRow + l[:line] - 1
    gotoitem(text, path, line)
  end
end

function gotoitem(text, file, line = 0, secondary = "")
  Dict(
    :text      => text,
    :file      => file,
    :line      => line,
    :secondary => secondary
  )
end

function toplevelgotoitem(mod, word)
  (entrypath = Base.find_package(string(mod))) === nothing && return []

  bindpathmaps = searchtoplevelbindings(entrypath)

  filter!(bindpathmaps) do bindpathmap
    expr = bindpathmap[1].expr
    binding = CSTParser.bindingof(expr)
    if binding === nothing
      false
    else
      name = binding.name
      word == name
    end
  end
  map(gotoitem, bindpathmaps)
end

function searchtoplevelbindings(path, bindpathmaps = [])
  text = read(path, String)
  parsed = CSTParser.parse(text, true)
  currentbindings = toplevel_bindings(parsed, text)
  append!(bindpathmaps, map(binding -> (binding, path), currentbindings))

  for binding in currentbindings
    expr = binding.expr
    if isinclude(expr)
      nextfile = expr.args[3].val
      nextpath = joinpath(dirname(path), nextfile)
      searchtoplevelbindings(nextpath, bindpathmaps)
    end
  end

  bindpathmaps
end

function gotoitem(bindpathmap::Tuple{ToplevelBinding, String})
  bind = bindpathmap[1]
  expr = bind.expr
  text = CSTParser.bindingof(expr).name
  if CSTParser.has_sig(expr)
    sig = CSTParser.get_sig(expr)
    text = str_value(sig)
  end
  file = bindpathmap[2]
  line = bind.lines.start - 1
  secondary = file * ":" * string(line)
  gotoitem(text, file, line, secondary)
end

function methodgotoitem(mod, word)
  ms = @errs getmethods(mod, word)
  if ms isa EvalError
    []
  else
    map(gotoitem, aggregatemethods(ms))
  end
end

# aggregate methods with default arguments to the ones with full arguments
aggregatemethods(f) = aggregatemethods(methods(f))
aggregatemethods(ms::MethodList) = aggregatemethods(collect(ms))
function aggregatemethods(ms::Vector{Method})
  ms = sort(ms, by = m -> m.nargs, rev = true)
  unique(m -> (m.file, m.line), ms)
end

function gotoitem(m::Method)
  _, link = view(m)
  sig = sprint(show, m)
  text = replace(sig, r" in .* at .*$" => "")
  file = link.file
  line = link.line - 1
  secondary = join(link.contents)
  gotoitem(text, file, line, secondary)
end
