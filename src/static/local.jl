#=
Find local bindings

Downstreams: completions.jl, goto.jl, datatip.jl, refactor.jl
=#


struct LocalBinding
    name::String
    verbatim::String
    span::UnitRange{Int}
    line::Int
    expr::EXPR
end

struct LocalScope
    name::String
    verbatim::String
    span::UnitRange{Int}
    line::Int
    children::Vector{Union{LocalBinding,LocalScope}}
    expr::EXPR
end

const LocalBS = Union{LocalBinding,LocalScope}

struct ActualLocalBinding
    name::String
    verbatim::String
    root::String
    line::Int
    locality::Float64
    expr::EXPR
end
function ActualLocalBinding(bs::LocalBS, root::String, line::Integer, byteoffset::Integer)
    locality = distance(line, byteoffset, bs.line, bs.span)
    return ActualLocalBinding(bs.name, bs.verbatim, root, bs.line, locality, bs.expr)
end

"""
    locals(text::String, line::Integer, col::Integer)::Vector{ActualLocalBinding}

Returns local bindings in `text`, while computing localities based on `line` and `col`.
"""
function locals(text::String, line::Integer, col::Integer)::Vector{ActualLocalBinding}
    expr = CSTParser.parse(text, true)
    traverse_expr!(expr)
    bindings = localbindings(expr, text)
    actual_localbindings(bindings, line, byteoffset(text, line, col))
end

function localbindings(expr, text, bindings = LocalBS[], pos = 1, line = 1)
    # binding
    bind = bindingof(expr)
    hs = hasscope(expr)
    if bind !== nothing && !hs
        verbatim = str_value_verbatim(bind, text, pos)
        range = pos:pos+expr.span
        push!(bindings, LocalBinding(bind.name, verbatim, range, line, expr))
    end

    if hs
        typof(expr) === CSTParser.Kw && return bindings

        # destructure multiple returns
        if ismultiplereturn(expr)
            for arg in expr
                # don't update `pos` & `line`, i.e.: treat all the multiple returns as same
                localbindings(arg, text, bindings, pos, line)
            end
        # properly detect the parameters of a method with where clause: https://github.com/JunoLab/Juno.jl/issues/404
        elseif iswhereclause(expr)
            for arg in expr
                localbindings(arg, text, bindings, pos, line)
                line += counteols_in_expr(arg, text, pos)
                pos += arg.fullspan
            end
        else
            # find local binds in a scope
            # calculate fields for `LocalScope` first
            verbatim = str_value_verbatim(expr, text, pos)
            range = pos:pos+expr.span
            name = bind === nothing ? "" : bind.name

            children = LocalBS[]
            for arg in expr
                localbindings(arg, text, children, pos, line)
                line += counteols_in_expr(arg, text, pos)
                pos += arg.fullspan
            end

            push!(bindings, LocalScope(name, verbatim, range, line, children, expr))
        end

        return bindings
    end

    # look for more local bindings if exists
    for arg in expr
        localbindings(arg, text, bindings, pos, line)
        line += counteols_in_expr(arg, text, pos)
        pos += arg.fullspan
    end

    return bindings
end

function byteoffset(text, line, col)
    byteoffset = 1
    current_line = 1
    current_char = 0
    for c in text
        if line == current_line
            current_char += 1
            c === '\n' && break
        end
        current_char == col && break
        byteoffset += @static VERSION >= v"1.1" ? ncodeunits(c) : ncodeunits(string(c))
        c === '\n' && (current_line += 1)
    end
    byteoffset
end

function actual_localbindings(bindings, line, byteoffset)
    actual_bindings = _actual_localbindings(bindings, line, byteoffset)

    filter!(b -> !isempty(b.name), actual_bindings)
    sort!(actual_bindings, lt = (b1, b2) -> b1.locality < b2.locality)
    return @static VERSION ≥ v"1.1" ? unique!(b->b.name, actual_bindings) : unique(b->b.name, actual_bindings)
end
function _actual_localbindings(bindings, line, byteoffset, root = "", actual_bindings = ActualLocalBinding[])
    for bind in bindings
        push!(actual_bindings, ActualLocalBinding(bind, root, line, byteoffset))
        if bind isa LocalScope && byteoffset in bind.span
            _actual_localbindings(bind.children, line, byteoffset, bind.name, actual_bindings)
        end
    end

    return actual_bindings
end

function distance(line, byteoffset, defline, defspan)
    abslinediff = abs(line - defline)
    absbytediff = abs(byteoffset - defspan[1]) # tiebreaker for bindings on the same line
    diff = if byteoffset in defspan
        Inf
    elseif line < defline
        (defline - line)*10 # bindings defined *after* the current line have a lower priority
    else
        line - defline
    end
    diff + absbytediff*1e-6
end
