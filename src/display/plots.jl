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

@require Compose begin
  @render PlotPane img::Compose.Context begin
    HTML(stringmime(MIME"image/svg+xml"(), img))
  end

  @render e::Editor img::Compose.Context begin
    Text("Compose.Context(...)")
  end
end
