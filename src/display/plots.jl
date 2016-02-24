type PlotPane end

render(::PlotPane, x; options = d()) =
  @msg plot(render(Inline(), x, options = options))

@init setdisplay(Media.Graphical, PlotPane())

@require Gadfly begin
  @render PlotPane p::Gadfly.Plot begin
    div(d(:style=>"background: white"),
        HTML(stringmime("text/html", p)))
  end
end

@require Images begin
  @render PlotPane img::Images.Image begin
    HTML() do io
      print(io, """<img src="data:image/png;base64,""")
      print(io, stringmime(MIME"image/png"(), img))
      print(io, "\" />")
    end
  end
end
