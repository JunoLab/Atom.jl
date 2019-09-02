using CSTParser

handle("outline") do text
    return outline(text)
end

function outline(text)
    parsed = CSTParser.parse(text, true)
    toplevel_bindings(parsed, text)
end

function toplevel_bindings(expr, text, bindings = [], line = 1, pos = 1)
    bind = CSTParser.bindingof(expr)
    if bind !== nothing
        push!(bindings, (bind.name, line:(line + count(c -> c === '\n', text[nextind(text, pos - 1):prevind(text, pos + expr.span)]))))
    end
    scope = CSTParser.scopeof(expr)
    if scope !== nothing && !(expr.typ === CSTParser.FileH || expr.typ === CSTParser.ModuleH || expr.typ === CSTParser.BareModule)
        return bindings
    end
    if expr.args !== nothing
        for arg in expr.args
            toplevel_bindings(arg, text, bindings, line, pos)
            line += count(c -> c === '\n', text[nextind(text, pos - 1):prevind(text, pos + arg.fullspan)])
            pos += arg.fullspan
        end
    end
    return bindings
end

struct LocalScope
    name
    span
    children
end

struct LocalBinding
    name
    span
end

function local_bindings(expr, bindings = [], pos = 1)
    bind = CSTParser.bindingof(expr)
    scope = CSTParser.scopeof(expr)
    if bind !== nothing && scope === nothing
        push!(bindings, LocalBinding(bind.name, pos:pos+expr.span))
    end
    if scope !== nothing
        range = pos:pos+expr.span
        localbindings = []
        if expr.args !== nothing
            for arg in expr.args
                local_bindings(arg, localbindings, pos)

                pos += arg.fullspan
            end
        end
        push!(bindings, LocalScope(bind === nothing ? "" : bind.name, range, localbindings))
        return bindings
    elseif expr.args !== nothing
        for arg in expr.args
            local_bindings(arg, bindings, pos)
            pos += arg.fullspan
        end
    end
    return bindings
end

function locals(text, line, col)
    byteoffset = 1
    current_line = 1
    current_char = 0
    for c in text
        if line == current_line
            current_char += 1
            c === '\n' && break
        end
        current_char == col && break
        byteoffset += VERSION >= v"1.1" ? ncodeunits(c) : ncodeunits(string(c))
        c === '\n' && (current_line += 1)
    end
    parsed = CSTParser.parse(text, true)

    bindings = local_bindings(parsed)
    bindings = filter_local_bindings(bindings, byteoffset)
    bindings = filter(x -> !isempty(x[1]), bindings)
    bindings = sort(bindings, lt = (a,b) -> a[3] < b[3])
    bindings = unique(x -> x[1], bindings)
    bindings = map(x -> x[1:2], bindings)

    bindings
end

function filter_local_bindings(bindings, byteoffset, root = "", actual_bindings = [])
    for bind in bindings
        push!(actual_bindings, (bind.name, root, abs(bind.span[1] - byteoffset)))
        if bind isa LocalScope && byteoffset in bind.span
            filter_local_bindings(bind.children, byteoffset, bind.name, actual_bindings)
        end
    end
    actual_bindings
end
