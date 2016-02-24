type PlotPane end

render(::PlotPane, x; options = d()) =
  @msg plot(render(Inline(), x, options = options))

@require Gadfly begin
  setdisplay(Gadfly.Plot, PlotPane())

  @render PlotPane p::Gadfly.Plot begin
    div(d(:style=>"background: white"),
        HTML(stringmime("text/html", p)))
  end
end
