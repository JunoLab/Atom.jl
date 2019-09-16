using REPL, Base64

struct JunoDisplay <: AbstractDisplay end

function plotpane_io_ctx(io::IO)
  info = @rpc plotsize()
  if info isa Array
    size = info
    dpi = 1
  else
    size = info["size"]
    dpi = info["ratio"]
  end
  size .-= 1

  IOContext(io, :juno_plotsize => size, :juno_dpi_ratio => dpi, :juno_colors => syntaxcolors())
end

const plain_mimes = [
  "image/png",
  "image/jpeg",
  "image/tiff",
  "image/bmp",
  "image/gif"
]

const plotpane_mime = "application/prs.juno.plotpane+html"
const jlpane_mime = "application/prs.juno.jlpane"

function displayinplotpane(x)
  # allow openening a new pane in Atom
  if showable("application/prs.juno.jlpane", x)
    msg("jlpane", x.id, x.opts)
    return true
  end

  PlotPaneEnabled[] || return false

  legacy_plotpane = false
  # Juno-specific display always takes precedence
  if showable("application/juno+plotpane", x) && !showable(plotpane_mime, x)
    legacy_plotpane = true
    m = which(show, (IO, MIME"application/juno+plotpane", typeof(x)))
    @warn("""
      The \"application/juno+plotpane\" MIME type is deprecated. Please use \"$(plotpane_mime)\" instead.
    """, maxlog=1, _id=:juno_plotpane_legacy, _file=string(m.file), _line=m.line, _module=m.module)
  end
  if showable(plotpane_mime, x) || legacy_plotpane
    try
      io = IOBuffer()
      show(plotpane_io_ctx(io), legacy_plotpane ? "application/juno+plotpane" : plotpane_mime, x)
      str = String(take!(io))
      startswith(str, "data:") || (str = string("data:text/html,", str))
      @msg ploturl(str)
      return true
    catch err
      err isa MethodError && err.f == Base.show || rethrow(err)
    end
  end
  # xml should be in a webview as well because of the possibility of embedded JS
  if showable("image/svg+xml", x)
    try
      io = IOBuffer()
      # render(PlotPane(), HTML(string("data:image/svg+xml,", stringmime("image/svg+xml", x, context=plotpane_io_ctx(io)))))
      @msg ploturl(string("data:image/svg+xml,", stringmime("image/svg+xml", x, context=plotpane_io_ctx(io))))
      return true
    catch err
      err isa MethodError && err.f == Base.show || rethrow(err)
    end
  end

  # images
  for mime in plain_mimes
    if showable(mime, x)
      try
        io = IOBuffer()
        suffix = istextmime(mime) ? "," : ";base64,"
        str = stringmime(mime, x, context=plotpane_io_ctx(io))
        str = string("<img src=\"data:", mime, suffix, str, "\">")
        render(PlotPane(), HTML(str))
        return true
      catch err
        err isa MethodError && err.f == Base.show || rethrow(err)
      end
    end
  end
  return false
end

using TreeViews: hastreeview, numberofnodes, treelabel, treenode, nodelabel

# called in user code and in REPL
function Base.display(d::JunoDisplay, m::MIME{T}, x) where T
  displayable(d, m) || throw(MethodError(display, (d, m, x)))
  Base.display(d::JunoDisplay, x)
end

Base.displayable(d::JunoDisplay, m::MIME"application/juno+inline") = true
Base.displayable(d::JunoDisplay, m::MIME"application/prs.juno.inline") = true

Base.displayable(d::JunoDisplay, m::MIME"application/juno+plotpane") = PlotPaneEnabled[]
Base.displayable(d::JunoDisplay, m::MIME"application/prs.juno.plotpane+html") = PlotPaneEnabled[]
Base.displayable(d::JunoDisplay, m::MIME"image/svg+xml") = PlotPaneEnabled[]
Base.displayable(d::JunoDisplay, m::MIME"application/prs.juno.jlpane") = true

function Base.displayable(d::JunoDisplay, m::MIME{T}) where T
  string(T) in plain_mimes ? PlotPaneEnabled[] : false
end

function Base.display(d::JunoDisplay, x)
  d = last(filter(x -> (x isa REPL.REPLDisplay), Base.Multimedia.displays))
  if displayinplotpane(x)
    # we shouldn't need to do this, but Plots.jl has a ugly overload on display(::REPLDisplay, ::MIME"text/plain" ::Plot)
    # which would otherwise be used
    inREPL[] && invoke(display, Tuple{typeof(d), typeof(MIME"text/plain"()), Any}, d, MIME"text/plain"(), x)
    # throw(MethodError(display, "nope"))
  else
    throw(MethodError(display, (x,)))
  end
  return nothing
end

# called when displaying results in the editor
function displayandrender(res)
  if !displayinplotpane(res)
    old = customdisplaystack()
    try
      display(res)
    catch e
    end
    restoredisplaystack(old)
  end

  if hastreeview(res)
    res = generateTreeView(res)
  end
  render′(Editor(), res)
end

function customdisplaystack()
  old = copy(Base.Multimedia.displays)
  filter!(Base.Multimedia.displays) do d
    !(d isa REPL.REPLDisplay || d isa TextDisplay ||
      d isa JunoDisplay || d isa Media.DisplayHook)
  end
  old
end

function restoredisplaystack(old)
  empty!(Base.Multimedia.displays)
  foreach(pushdisplay, old)
end

function bestlabel(f, args...)
  if applicable(f, IOBuffer(), args..., MIME"application/prs.juno.inline"())
    return HTML(sprint(f, args..., MIME"application/prs.juno.inline"()))
  elseif applicable(f, IOBuffer(), args..., MIME"application/juno+inline"()) # deprecated
    m = which(f, (IO, typeof.(args)..., MIME"application/juno+inline"));
    @warn("""
      The \"application/juno+inline\" MIME type is deprecated. Please use \"application/prs.juno.inline\" instead.
    """, maxlog=1, _id=:juno_tree_legacy, _file=string(m.file), _line=m.line, _module=m.module);
    return HTML(sprint(f, args..., MIME"application/juno+inline"()))
  elseif applicable(f, IOBuffer(), args..., MIME"text/html"())
    return HTML(sprint(f, args..., MIME"text/html"()))
  else
    return Text(sprint(f, args..., MIME"text/plain"()))
  end
end

# TreeViews.jl -> Juno.LazyTree
function generateTreeView(x)
  header = bestlabel(treelabel, x)

  numberofnodes(x) == 0 &&  return Tree(header, [])

  genchildren = function ()
    children = Any[]
    for i in 1:numberofnodes(x)
      node = treenode(x, i)
      cheader = bestlabel(nodelabel, x, i)

      if isempty(cheader.content)
        node === missing && continue
        push!(children, hastreeview(node) ? generateTreeView(node) : node)
      elseif node === missing
        push!(children, cheader)
      else
        push!(children, SubTree(Row(cheader, text" → "), hastreeview(node) ? generateTreeView(node) : node))
      end
    end
    children
  end

  return LazyTree(header, genchildren)
end
