using CodeTools, LNR

import CodeTools: getblock

LNR.cursor(data::Associative) = cursor(data["row"], data["column"])

handle("module") do data
  main = haskey(data, "held") ? data["held"] :
         haskey(data, "path") ? CodeTools.filemodule(data["path"]) :
         "Main"
  main == "" && (main = "Main")
  sub = CodeTools.codemodule(data["code"], cursor(data))
  return @d(:main => main,
            :sub  => sub,
            :inactive => CodeTools.getthing(main) == nothing,
            :subInactive => CodeTools.getthing("$main.$sub") == nothing)
end

handle("all-modules") do _
  [string(m) for m in CodeTools.allchildren(Main)]
end

handle("eval-block") do data
  code = data["code"]
  block, bounds = getblock(code, data["row"])
  display(include_string(Main, block))
end
