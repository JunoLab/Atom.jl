using REPL, Base64

struct JunoDisplay <: AbstractDisplay end

struct JunoEditorInput
  x::Any
end

plotpane_io_ctx(io::IO) = IOContext(io, :juno_plotsize => plotsize(), :juno_colors => syntaxcolors())

const plain_mimes = [
  "image/png",
  "image/jpeg",
  "image/tiff",
  "image/bmp",
  "image/gif"
]

function displayinplotpane(x)
  io = IOBuffer()

  # Juno-specific display always takes precedence
  if showable("application/juno+plotpane", x)
    show(plotpane_io_ctx(io), "application/juno+plotpane", x)
    str = String(take!(io))
    startswith(str, "data:") || (str = string("data:text/html,", str))
    @msg ploturl(str)
    return true
  end
  # xml should be in a webview as well because of the possibility of embedded JS
  if showable("image/svg+xml", x)
    @msg ploturl(string("data:image/svg+xml,", stringmime("image/svg+xml", x, context=plotpane_io_ctx(io))))
    return true
  end

  # images
  for mime in plain_mimes
    if showable(mime, x)
      suffix = istextmime(mime) ? "," : ";base64,"
      str = string("<img src=\"data:", mime, suffix, stringmime(mime, x, context=plotpane_io_ctx(io)), "\">")
      render(PlotPane(), HTML(str))
      return true
    end
  end
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
  header = applicable(treelabel, IOBuffer(), x, MIME"text/html"()) ?
            HTML(sprint(treelabel, x, MIME"text/html"())) :
            Text(sprint(treelabel, x, MIME"text/plain"()))

  numberofnodes(x) == 0 &&  return Tree(header, [])

  genchildren = function ()
    children = Any[]
    for i in 1:numberofnodes(x)
      node = treenode(x, i)

      cheader = applicable(treelabel, IOBuffer(), x, i, MIME"text/html"()) ?
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
