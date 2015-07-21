using CodeTools, LNR

import CodeTools: getblock, getthing

LNR.cursor(data::Associative) = cursor(data["row"], data["column"])

function modulenames(data, pos)
  main = haskey(data, "module") ? data["module"] :
         haskey(data, "path") ? CodeTools.filemodule(data["path"]) :
         "Main"
  main == "" && (main = "Main")
  sub = CodeTools.codemodule(data["code"], pos)
  main, sub
end

function getmodule(data, pos)
  main, sub = modulenames(data, pos)
  getthing("$main.$sub", getthing(main, Main))
end

handle("module") do data
  main, sub = modulenames(data, cursor(data))
  return @d(:main => main,
            :sub  => sub,
            :inactive => getthing(main) == nothing,
            :subInactive => getthing("$main.$sub") == nothing)
end

handle("all-modules") do _
  [string(m) for m in CodeTools.allchildren(Main)]
end

isselection(data) = data["start"] ≠ data["end"]

handle("eval") do data
  mod = getmodule(data, cursor(data["start"]))
  block, (start, stop) = isselection(data) ?
                    getblock(data["code"], cursor(data["start"]), cursor(data["end"])) :
                    getblock(data["code"], data["start"]["row"])
  display(include_string(mod, block, get(data, "path", "untitled"), start))
  start, stop
end

handle("eval-all") do data
  mod = Main
  if haskey(data, "module")
    mod = getthing(data["module"], Main)
  elseif haskey(data, "path")
    mod = getthing(CodeTools.filemodule(data["path"]), Main)
  end
  include_string(mod, data["code"], get(data, "path", "untitled"))
  return
end
