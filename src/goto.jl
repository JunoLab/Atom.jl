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

  # toplevel items -- toplevel variables within the module & methods
  toplevelitems = toplevelgotoitem(mod, word)
  isempty(toplevelitems) || return Dict(:error => false, :items => toplevelitems)

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

function toplevelgotoitem(mod, word)
  methodgotoitem(mod, word)
  # TODO look through toplevel bindings via CSTParser and enables variable jumps
end

function methodgotoitem(mod, word)
  ms = @errs getmethods(mod, word)
  if ms isa EvalError
    []
  else
    map(m -> gotoitem(m), aggregatemethods(ms))
  end
end

# aggregate methods with default arguments to the ones with full arguments
aggregatemethods(f) = aggregatemethods(methods(f))
aggregatemethods(ms::MethodList) = aggregatemethods(collect(ms))
function aggregatemethods(ms::Vector{Method})
  ms = sort(ms, by = m -> m.nargs, rev = true)
  unique(m -> (m.file, m.line), ms)
end

function gotoitem(text, file, line = 0, secondary = "")
  Dict(
    :text      => text,
    :file      => file,
    :line      => line,
    :secondary => secondary
  )
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
