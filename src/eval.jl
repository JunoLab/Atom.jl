using CodeTools, LNR, Media

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
            :inactive => (getthing(main) == nothing),
            :subInactive => (getthing("$main.$sub") == nothing))
end

handle("all-modules") do _
  sort!([string(m) for m in CodeTools.allchildren(Main)])
end

isselection(data) = data["start"] ≠ data["end"]

handle("eval") do data
  @dynamic let Media.input = Editor()
    mod = getmodule(data, cursor(data["start"]))
    block, (start, stop) = isselection(data) ?
                             getblock(data["code"], cursor(data["start"]), cursor(data["end"])) :
                             getblock(data["code"], data["start"]["row"])
    !isselection(data) && msg("show-block", @d(:start=>start, :end=>stop))
    result = @errs include_string(mod, block, get(data, "path", "untitled"), start)
    @d(:start => start,
       :end => stop,
       :result => render(Editor(), result))
   end
end

handle("eval-all") do data
  @dynamic let Media.input = Editor()
    mod = Main
    if haskey(data, "module")
      mod = getthing(data["module"], Main)
    elseif haskey(data, "path")
      mod = getthing(CodeTools.filemodule(data["path"]), Main)
    end
    try
      include_string(mod, data["code"], get(data, "path", "untitled"))
    catch e
      msg("error", @d(:msg => "Error evaluating $(basename(get(data, "path", "untitled")))",
                      :detail => sprint(showerror, e, catch_backtrace())))
    end
  end
  return
end

handle("eval-repl") do data
  @dynamic let Media.input = Console()
    mode = get(data, "mode", nothing)
    if mode == "shell"
      data["code"] = "run(`$(data["code"])`)"
    elseif mode == "help"
      data["code"] = "@doc $(data["code"])"
    end
    try
      render(include_string(data["code"]))
    catch e
      showerror(STDERR, e, catch_backtrace())
    end
  end
end
