using CodeTools, LNR

import CodeTools: getblock

LNR.cursor(data::Associative) = cursor(data["row"], data["column"])

handle("eval-block") do data
  code = data["code"]
  block, bounds = getblock(code, data["row"])
  display(include_string(Main, block))
end
