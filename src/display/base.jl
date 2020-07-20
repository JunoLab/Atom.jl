using Hiccup
using Base64

render(e::Editor, ::Nothing) = render(e, icon("check"))

render(::Console, ::Nothing) = nothing

render(::Inline, x::Union{Float16, Float32, Float64}) =
  isnan(x) || isinf(x) ?
    view(span(".syntax--constant.syntax--numeric", string(x))) :
    Dict(:type => :number, :value => float(x), :full => string(x))

@render Inline x::Expr begin
  text = string(x)
  length(split(text, "\n")) == 1 ?
    Model(Dict(:type => :code, :text => text)) :
    Tree(Text("Code"),
         [Model(Dict(:type => :code, :text => text, :attrs => Dict(:block => true)))])
end

render(::Console, x::Expr) =
  Atom.msg("result", Dict(:type => :code, :text => string(x), :attrs => Dict(:block => true)))

@render Inline x::Text begin
  ls = split(chomp(string(x)), "\n")
  length(ls) > 1 ?
    Tree(Model(ls[1]), c(Model(join(ls[2:end], "\n")))) :
    span(ls[1])
end

showmethod(args...) = which(show, (IO, args...))

const inline_mime = "application/prs.juno.inline"

@render Inline x begin
  fields = fieldnames(typeof(x))

  legacy_inline = false
  # Juno-specific display always takes precedence
  if showable("application/juno+inline", x) && !showable(inline_mime, x)
    legacy_inline = true
    m = which(show, (IO, MIME"application/juno+inline", typeof(x)))
    @warn("""
      The \"application/juno+inline\" MIME type is deprecated. Please use \"$(inline_mime)\" instead.
    """, maxlog=1, _id=:juno_inline_legacy, _file=string(m.file), _line=m.line, _module=m.module)
  end
  if showable(inline_mime, x) || legacy_inline
    io = IOBuffer()
    x′ = show(IOContext(io, :limit => true, :color => true), legacy_inline ? MIME"application/juno+inline"() : inline_mime, x)
    if !(x′ isa Nothing)
      defaultrepr(x′, true)
    else
      Text(String(take!(io)))
    end
  elseif showmethod(MIME"text/plain", typeof(x)) ≠ showmethod(MIME"text/plain", Any)
    Text(filter(isvalid, strlimit(sprint(io -> show(IOContext(io, :limit => true, :color => true), MIME"text/plain"(), x)), 2000)))
  elseif showmethod(typeof(x)) ≠ showmethod(Any)
    Text(filter(isvalid, strlimit(sprint(io -> show(IOContext(io, :limit => true, :color => true), x)), 2000)))
  else
    defaultrepr(x, true)
  end
end

_fieldlist(x, fields=fieldnames(typeof(x))) = [SubTree(Text("$f → "), getfield′(x, f, UNDEF)) for f in fields]

function defaultrepr(x, lazy = false, typerepr = typeof(x))
  fields = fieldnames(typeof(x))
  if isempty(fields)
    span(c(render(Inline(), typerepr), "()"))
  else
    lazy ? LazyTree(typerepr, () -> _fieldlist(x,fields)) :
           Tree(typerepr, _fieldlist(x,fields))
  end
end

typ(x) = span(".syntax--support.syntax--type", x)

@render Inline x::Type typ(string(x))

for A in :[Vector, Matrix, AbstractVector, AbstractMatrix].args
  @eval begin
    render(i::Inline, ::Type{$A}) =
      render(i, typ($(string(A))))
    (render(i::Inline, ::Type{$A{T}}) where T) =
      render(i, typ(string($(string(A)), "{$T}")))
  end
end

@render Inline x::Module span(".syntax--keyword.syntax--other", string(x))

@render Inline x::Symbol span(".syntax--constant.syntax--other.syntax--symbol", repr(x))

@render Inline x::Char span(".syntax--string.syntax--quoted.syntax--single", escape_string("'$x'"))

@render Inline x::VersionNumber span(".syntax--string.syntax--quoted.syntax--other", sprint(show, x))

@render Inline _::Nothing span(".syntax--constant", "nothing")

@render Inline _::Missing span(".syntax--constant", "missing")

@render Inline _::Undefined span(".fade", "<undefined>")

import Base.Docs: doc

isanon(f) = startswith(string(typeof(f).name.mt.name), "#")

# functions where `!hascompactrepr(f)` may display closed-over variables in
# `repr(f)` which might take a very long time
function hascompactrepr(f)
  mt = typeof(f).name.mt
  # this condition is copied from the implementation of Base.show_function
  isdefined(mt, :module) && isdefined(mt.module, mt.name) && getfield(mt.module, mt.name) === f
end
_displayname(f) = isanon(f) ? "λ" : hascompactrepr(f) ? repr(f) : string(nameof(f))

@render i::Inline f::Function begin
  name = nameof(f)
  mdl = typeof(f).name.module
  binding = Docs.Binding(mdl, name)
  LazyTree( span(".syntax--support.syntax--function", _displayname(f)),
    ()-> [(CodeTools.hasdoc(binding) ? [md_hlines(doc(binding))] : []);
          methods(f);
          _fieldlist(f)]
  )
end

@render Inline f::Core.IntrinsicFunction begin
  id = Core.Intrinsics.bitcast(Int32, f)
  span(c(span(".syntax--support.syntax--function", string(f)), " (intrinsic function #$id)"))
end

@render Inline f::Core.Builtin begin
  LazyTree(
    span(c(span(".syntax--support.syntax--function", string(f)), " (built-in function)")),
    ()->[(CodeTools.hasdoc(f) ? [md_hlines(doc(f))] : [])..., methods(f)]
  )
end

# TODO: lazy load a recursive tree
function trim(xs, len = 25)
  if length(xs) ≤ len
    undefs(xs)
  else
    [undefs(xs[1:(len÷2 - iseven(len))]); fade("..."); undefs(xs[end-(len÷2 - 1):end])]
  end
end

pluralize(n::Integer, one, more=one) = string(n, " ", n == 1 ? one : more)
pluralize(xs, one, more=one) = pluralize(length(xs), one, more)

@render i::Inline xs::Vector begin
    LazyTree(span(c(render(i, typeof(xs)), Atom.fade(" with $(pluralize(xs, "element", "elements"))"))), () -> trim(xs))
end

@render i::Inline xs::Set begin
    LazyTree(span(c(render(i, typeof(xs)), Atom.fade(" with $(pluralize(xs, "element", "elements"))"))), () -> trim(collect(xs)))
end

@render Inline xs::AbstractArray begin
  Text(sprint(io -> show(IOContext(io, :limit=>true), MIME"text/plain"(), xs)))
end

@render i::Inline d::AbstractDict begin
  cs = () -> begin
    j = 0
    st = Array{Atom.SubTree}(undef, 0)
    for (key, val) in d
      push!(st, SubTree(span(c(render(i, key), " => ")), val))
      j += 1
      j > 25 && (push!(st, SubTree(span("... => "), span("..."))); break)
    end
    return st
  end
  LazyTree(span(c(typ(string(nameof(typeof(d)),
            "{$(eltype(d).parameters[1]), $(eltype(d).parameters[2])}")), Atom.fade(" with $(pluralize(d, "entry", "entries"))"))), cs)
end

@render Inline x::Number span(".syntax--constant.syntax--numeric", sprint(show, x))

@render i::Inline x::Complex begin
  re, ima = reim(x)
  if signbit(ima)
    span(c(render(i, re), " - ", render(i, -ima), "im"))
  else
    span(c(render(i, re), " + ", render(i, ima), "im"))
  end
end

@render Inline p::Ptr begin
  Row(Atom.fade(string(typeof(p))), Text(" @"),
       span(".syntax--constant.syntax--numeric", c("0x$(string(UInt(p), base=16, pad=Sys.WORD_SIZE>>2))")))
end

# TODO: lazy load the rest of the string
@render i::Inline x::AbstractString begin
  x = collect(x)
  length(x) ≤ 500 ?
    span(".syntax--string", c(render(i, Text(stringmime("text/plain", join(x)))))) :
    Row(span(".syntax--string", c("\"", render(i, Text(escape_string(join(x[1:min(length(x),500)])))))),
        Text("..."))
end

render(i::Inline, x::Irrational{sym}) where sym =
  render(i, span(c(string(sym), " = ", render(i, float(x)), "...")))

@render i::Inline xs::Tuple begin
  if length(xs) === 1
    span(c("(", render(i, first(xs)), ",)"))
  else
    span(c("(", interpose(map(x->render(i, x), xs), ", ")..., ")"))
  end
end

include("methods.jl")
include("markdown.jl")
