import Juno: PlotPane

@init setdisplay(Media.Graphical, PlotPane())

@require Images begin
  @render PlotPane img::Images.Image begin
    HTML() do io
      print(io, """<img src="data:image/png;base64,""")
      print(io, stringmime(MIME"image/png"(), img))
      print(io, "\" />")
    end
  end
end

@require Vega begin
  @render Inline v::Vega.VegaVisualization Text("Vega Visualisation")
  @render Clipboard v::Vega.VegaVisualization Text("Vega Visualisation")
end
