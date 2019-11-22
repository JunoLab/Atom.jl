#=
Find local bindings

- downstreams: completions.jl, goto.jl, datatip.jl, refactor.jl
- TODO?
    create more structs to represent function/macro calls, and make each structs keeps
    minimum fields, and then each downstream construct information in need
=#


struct LocalBinding
    name::String
    bindstr::String
    span::UnitRange{Int64}
    line::Int
    expr::CSTParser.EXPR
end

struct LocalScope
    name::String
    bindstr::String
    span::UnitRange{Int64}
    line::Int
    children::Vector{Union{LocalBinding, LocalScope}}
    expr::CSTParser.EXPR
end

function locals(text, line, col)
    parsed = CSTParser.parse(text, true)
    bindings = localbindings(parsed, text)
    actual_localbindings(bindings, line, byteoffset(text, line, col))
end

function localbindings(expr, text, bindings = [], pos = 1, line = 1)
    # binding
    bind = bindingof(expr)
    scope = scopeof(expr)
    if bind !== nothing && scope === nothing
        bindstr = str_value_as_is(bind, text, pos)
        range = pos:pos+expr.span
        push!(bindings, LocalBinding(bind.name, bindstr, range, line, expr))
    end

    if scope !== nothing
        expr.typ == CSTParser.Kw && return bindings

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
                line += countlines(arg, text, pos)
                pos += arg.fullspan
            end
        else
            # find local binds in a scope
            # calculate fields for `LocalScope` first
            bindstr = str_value_as_is(expr, text, pos)
            range = pos:pos+expr.span
            name = bind === nothing ? "" : bind.name

            children = []
            for arg in expr
                localbindings(arg, text, children, pos, line)
                line += countlines(arg, text, pos)
                pos += arg.fullspan
            end

            push!(bindings, LocalScope(name, bindstr, range, line, children, expr))
        end

        return bindings
    end

    # look for more local bindings if exists
    for arg in expr
        localbindings(arg, text, bindings, pos, line)
        line += countlines(arg, text, pos)
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

    filter!(b -> !isempty(b[:name]), actual_bindings)
    sort!(actual_bindings, lt = (b1, b2) -> b1[:locality] < b2[:locality])
    unique(b -> b[:name], actual_bindings)
end
function _actual_localbindings(bindings, line, byteoffset, root = "", actual_bindings = [])
    for bind in bindings
        push!(actual_bindings, Dict(
            :name     => bind.name,
            :bindstr  => bind.bindstr,
            :root     => root,
            :line     => bind.line,
            :locality => distance(line, byteoffset, bind.line, bind.span),
            :icon     => static_icon(bind.expr),
            :type     => static_type(bind.expr),
        ))
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
