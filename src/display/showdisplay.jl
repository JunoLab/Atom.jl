using REPL

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
  else
    didDisplay = false
  end
  didDisplay
end


function Base.display(d::JunoDisplay, x)
  displayinplotpane(x)
  display(last(filter(x -> x isa REPL.REPLDisplay, Base.Multimedia.displays)), x)
end

using TreeViews: hastreeview, numberofnodes, treelabel, treenode

# input from in-editor eval
function Base.display(d::JunoDisplay, wrapper::JunoEditorInput)
  x = wrapper.x
  displayinplotpane(x)

  # TreeViews.jl compat
  if hastreeview(x)
    x = generateTreeView(x)
  end

  Juno.render(Juno.Editor(), x)
end

# TreeViews.jl -> Juno.LazyTree
function generateTreeView(x)
  buf = IOBuffer()

  header = applicable(treelabel, buf, x, MIME"text/html"()) ?
            HTML(sprint(treelabel, x, MIME"text/html"())) :
            Text(sprint(treelabel, x, MIME"text/plain"()))

  numberofnodes(x) == 0 &&  return Tree(header, [])

  genchildren = function ()
    children = Any[]
    for i in 1:numberofnodes(x)
      node = treenode(x, i)

      cheader = applicable(treelabel, buf, x, i, MIME"text/html"()) ?
                HTML(sprint(treelabel, x, i, MIME"text/html"())) :
                Text(sprint(treelabel, x, i, MIME"text/plain"()))
      if isempty(cheader.content)
        push!(children, hastreeview(node) ? generateTreeView(node) : node)
      elseif node === nothing
        push!(children, cheader)
      else
        push!(children, SubTree(Row(cheader, text" → "), hastreeview(node) ? generateTreeView(node) : node))
      end
    end
    children
  end

  return LazyTree(header, genchildren)
end
