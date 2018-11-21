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

getfield′(x, f) = isdefined(x, f) ? getfield(x, f) : UNDEF

showmethod(T) = which(show, (IO, T))

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
  elseif showmethod(typeof(x)) ≠ showmethod(Any)
    Text(io -> show(IOContext(io, :limit => true, :color => true), MIME"text/plain"(), x))
  else
    defaultrepr(x, true)
  end
end

function defaultrepr(x, lazy = false)
  fields = fieldnames(typeof(x))
  if isempty(fields)
    span(c(render(Inline(), typeof(x)), "()"))
  else
    lazy ? LazyTree(typeof(x), () -> [SubTree(Text("$f → "), getfield′(x, f)) for f in fields]) :
           Tree(typeof(x), [SubTree(Text("$f → "), getfield′(x, f)) for f in fields])
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

@render Inline x::Symbol span(".syntax--constant.syntax--other.syntax--symbol", ":$x")

@render Inline x::Char span(".syntax--string.syntax--quoted.syntax--single", escape_string("'$x'"))

@render Inline x::VersionNumber span(".syntax--string.syntax--quoted.syntax--other", sprint(show, x))

@render Inline _::Nothing span(".syntax--constant", "nothing")

import Base.Docs: doc

isanon(f) = occursin("#", string(f))

@render Inline f::Function begin
  isanon(f) ? span(".syntax--support.syntax--function", "λ") :
    LazyTree(span(".syntax--support.syntax--function", string(typeof(f).name.mt.name)),
             ()->[(Atom.CodeTools.hasdoc(f) ? [md_hlines(doc(f))] : [])..., methods(f)])
end

# TODO: lazy load a recursive tree
trim(xs, len = 25) =
  length(xs) ≤ 25 ? undefs(xs) :
                    [undefs(xs[1:10]); fade("..."); undefs(xs[end-9:end])]

@render i::Inline xs::Vector begin
    Tree(span(c(render(i, eltype(xs)), Atom.fade("[$(length(xs))]"))), trim(xs))
end

@render i::Inline xs::Set begin
    Tree(span(c(render(i, typeof(xs)), Atom.fade("[$(length(xs))]"))), trim(collect(xs)))
end

@render Inline xs::AbstractArray begin
  Text(sprint(io -> show(IOContext(io, :limit=>true), MIME"text/plain"(), xs)))
end

@render i::Inline d::AbstractDict begin
  j = 0
  st = Array{Atom.SubTree}(undef, 0)
  for (key, val) in d
    push!(st, SubTree(span(c(render(i, key), " → ")), val))
    j += 1
    j > 25 && (push!(st, SubTree(span("... → "), span("..."))); break)
  end
  Tree(span(c(strong(String(nameof(typeof(d)))),
            Atom.fade(" $(eltype(d).parameters[1]) → $(eltype(d).parameters[2]) with $(length(d)) entries"))), st)
end

@render Inline x::Number span(".syntax--constant.syntax--numeric", sprint(show, x))

@render i::Inline x::Complex begin
  re, ima = reim(x)
  span(c(render(i, re), signbit(ima) ? " - " : " + ", render(i, abs(ima)), "im"))
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

(render(i::Inline, x::Irrational{sym}) where sym) =
  render(i, span(c(string(sym), " = ", render(i, float(x)), "...")))

@render i::Inline xs::Tuple begin
  span(c("(", interpose(map(x->render(i, x), xs), ", ")..., ")"))
end

include("methods.jl")
include("markdown.jl")
