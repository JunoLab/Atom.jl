struct JunoDisplay <: AbstractDisplay end

struct JunoEditorInput
  x::Any
end

plotpaneioctxt(io::IO) = IOContext(io, :juno_plotsize => plotsize(), :juno_colors => syntaxcolors())

function displayinplotpane(x)
  didDisplay = true

  io = IOBuffer()
  if showable("image/png", x)
    show(plotpaneioctxt(io), "image/png", x)
    str = String(take!(io))
    Juno.render(Juno.PlotPane(), HTML("<img src=\"data:image/png;base64,$(str)\">"))
  elseif showable("application/juno+plotpane", x)
    show(plotpaneioctxt(io), "application/juno+plotpane", x)
    str = String(take!(io))
    @msg ploturl(str)
    # Juno.render(Juno.PlotPane(), )
  else
    didDisplay = false
  end
  didDisplay
end


function Base.display(d::JunoDisplay, x)
  displayinplotpane(x)
  # need to be a bit more intelligent about finding the REPL display
  display(Base.Multimedia.displays[2], x)
end

# input from in-editor eval
function Base.display(d::JunoDisplay, wrapper::JunoEditorInput)
  x = wrapper.x
  displayinplotpane(x)

  Juno.render(Juno.Editor(), x)
  # TreeViews.hastreeview(x) ?
  #                 treeview(d, x) :
  #                 sprint(io -> show(IOContext(io, limit = true), MIME"text/plain"(), x))
end
