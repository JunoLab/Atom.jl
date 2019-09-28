using CSTParser

### toplevel bindings - outlines ###

struct ToplevelBinding
    expr::CSTParser.EXPR
    name::String
    type::String
    icon::String
    lines::UnitRange{Int}
end

handle("outline") do text
    try
        outline(text)
    catch err
        []
    end
end

function outline(text)
    parsed = CSTParser.parse(text, true)
    bindings = toplevel_bindings(parsed, text)
    map(outlineitem, bindings)
end

function outlineitem(binding)
    Dict(
        :name  => binding.name,
        :type  => binding.type,
        :icon  => binding.icon,
        :lines => [binding.lines.start, binding.lines.stop]
    )
end

function toplevel_bindings(expr, text, bindings::Vector{ToplevelBinding} = Vector{ToplevelBinding}(), line = 1, pos = 1)
    bind = CSTParser.bindingof(expr)

    if bind !== nothing
        name = bind.name
        if CSTParser.has_sig(expr)
            sig = CSTParser.get_sig(expr)
            name = str_value(sig)
        end

        type = static_type(bind)
        icon = static_icon(bind)
        lines = line:line+countlines(expr, text, pos, false)
        push!(bindings, ToplevelBinding(expr, name, type, icon, lines))
    end

    if istoplevel(expr)
        destructuretupleh!(expr, bindings, text, line, pos)
        describetest!(expr, bindings, text, line, pos)
        findinclude!(expr, bindings, text, line, pos)
        return bindings
    end

    if expr.args !== nothing
        for arg in expr.args
            toplevel_bindings(arg, text, bindings, line, pos)
            line += countlines(arg, text, pos)
            pos += arg.fullspan
        end
    end
    return bindings
end

function istoplevel(expr)
    scopeof(expr) !== nothing &&
    !(
        expr.typ === CSTParser.FileH ||
        expr.typ === CSTParser.ModuleH ||
        expr.typ === CSTParser.BareModule
    )
end

function destructuretupleh!(expr, bindings, text, line, pos)
    if expr.typ === CSTParser.TupleH
        name = join((str_value(a) for a in expr.args if CSTParser.bindingof(a) !== nothing), ',')
        if !isempty(name)
            lines = line:line + countlines(expr, text, pos)
            push!(bindings, ToplevelBinding(expr, name, "variable", "v", lines))
        end
    end
end

function describetest!(expr, bindings, text, line, pos)
    if expr.typ === CSTParser.MacroCall && expr.args[1].val == "@testset"
        name = "@testset" * " " * str_value(expr.args[2])
        lines = line:line + countlines(expr, text, pos)
        push!(bindings, ToplevelBinding(expr, name, "module", "icon-checklist", lines))
    end
end

function findinclude!(expr, bindings, text, line, pos)
    if isinclude(expr)
        file = expr.args[3].val
        name = "include(" * file * ")"
        push!(bindings, ToplevelBinding(expr, name, "module", "icon-file", line:line))
    end
end

isinclude(expr) = expr.typ === CSTParser.Call && expr.args[1].val == "include"

### local bindings -- completions, goto ###
# TODO? create separate structs for each downstream ?

struct LocalBinding
    name::String
    str::String
    span::UnitRange{Int64}
    line::Int
    expr::CSTParser.EXPR
end

struct LocalScope
    name::String
    str::String
    span::UnitRange{Int64}
    line::Int
    children::Vector{Union{LocalBinding, LocalScope}}
    expr::CSTParser.EXPR
end

function locals(text, line, col)
    parsed = CSTParser.parse(text, true)
    bindings = local_bindings(parsed, text)
    bindings = filter_local_bindings(bindings, line, byteoffset(text, line, col))
    bindings = filter(x -> !isempty(x[:name]), bindings)
    bindings = sort(bindings, lt = (a,b) -> a[:locality] < b[:locality])
    bindings = unique(x -> x[:name], bindings)
    bindings
end

function local_bindings(expr, text, bindings = [], pos = 1, line = 1)
    bind = CSTParser.bindingof(expr)
    scope = scopeof(expr)
    if bind !== nothing && scope === nothing
        str = bindingstr(bind, text, pos)
        range = pos:pos+expr.span
        push!(bindings, LocalBinding(bind.name, str, range, line, expr))
    end

    if scope !== nothing
        if expr.typ == CSTParser.Kw
            return bindings
        end

        str = bindingstr(bind, text, pos)
        range = pos:pos+expr.span

        localbindings = []
        if expr.args !== nothing
            for arg in expr.args
                local_bindings(arg, text, localbindings, pos, line)
                line += countlines(arg, text, pos)
                pos += arg.fullspan
            end
        end

        destructuretupleh!(expr, bindings, localbindings)

        name = bind === nothing ? "" : bind.name
        push!(bindings, LocalScope(name, str, range, line, localbindings, expr))
        return bindings
    end

    if expr.args !== nothing
        for arg in expr.args
            local_bindings(arg, text, bindings, pos, line)
            line += countlines(arg, text, pos)
            pos += arg.fullspan
        end
    end

    return bindings
end

function destructuretupleh!(expr, bindings, localbindings)
    if expr.typ === CSTParser.TupleH && any(CSTParser.bindingof(a) !== nothing for a in expr.args)
        for leftsidebind in localbindings
            push!(bindings, leftsidebind)
        end
    end
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
        byteoffset += VERSION >= v"1.1" ? ncodeunits(c) : ncodeunits(string(c))
        c === '\n' && (current_line += 1)
    end
    byteoffset
end

function filter_local_bindings(bindings, line, byteoffset, root = "", actual_bindings = [])
    for bind in bindings
        push!(actual_bindings, Dict(
            #- completions -#
            :name     => bind.name,
            :root     => root,
            :locality => distance(line, byteoffset, bind.line, bind.span),
            :icon     => static_icon(bind.expr),
            :type     => static_type(bind.expr),
            #- goto & datatip - #
            :line     => bind.line,
            :str      => bind.str,
        ))
        if bind isa LocalScope && byteoffset in bind.span
            filter_local_bindings(bind.children, line, byteoffset, bind.name, actual_bindings)
        end
    end

    actual_bindings
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

### utils ###

function scopeof(expr)
    scope = CSTParser.scopeof(expr)
    if scope ≠ nothing
        return scope
    else
        # can remove this with CSTParser 0.6.3
        if expr.typ == CSTParser.BinaryOpCall && expr.args[2].kind == CSTParser.Tokens.ANON_FUNC
            return :anon
        end

        if expr.typ == CSTParser.Call && expr.parent ≠ nothing && scopeof(expr.parent) == nothing
            return :call
        end

        if expr.typ == CSTParser.MacroCall
            return :macro
        end

        if expr.typ == CSTParser.TupleH && expr.parent ≠ nothing && scopeof(expr.parent) == nothing
            return :tupleh
        end
    end
    return nothing
end

function Base.countlines(expr::CSTParser.EXPR, text::String, pos::Int, full::Bool = true; eol = '\n')
    s = nextind(text, pos - 1)
    e = prevind(text, pos + (full ? expr.fullspan : expr.span))
    count(c -> c === eol, text[s:e])
end

# adapted from https://github.com/julia-vscode/DocumentFormat.jl/blob/b7e22ca47254007b5e7dd3c678ba27d8744d1b1f/src/passes.jl#L108
function str_value(x)
    if x.typ === CSTParser.PUNCTUATION
        x.kind == CSTParser.Tokens.LPAREN && return "("
        x.kind == CSTParser.Tokens.LBRACE && return "{"
        x.kind == CSTParser.Tokens.LSQUARE && return "["
        x.kind == CSTParser.Tokens.RPAREN && return ")"
        x.kind == CSTParser.Tokens.RBRACE && return "}"
        x.kind == CSTParser.Tokens.RSQUARE && return "]"
        x.kind == CSTParser.Tokens.COMMA && return ","
        x.kind == CSTParser.Tokens.SEMICOLON && return ";"
        x.kind == CSTParser.Tokens.AT_SIGN && return "@"
        x.kind == CSTParser.Tokens.DOT && return "."
        return ""
    elseif x.kind === CSTParser.Tokens.TRIPLE_STRING
        return string("\"\"\"", x.val, "\"\"\"")
    elseif x.kind === CSTParser.Tokens.STRING
        return string("\"", x.val, "\"")
    elseif x.typ === CSTParser.Parameters
        return ";" * join(str_value(a) for a in x)
    elseif x.typ === CSTParser.IDENTIFIER || x.typ === CSTParser.LITERAL || x.typ === CSTParser.OPERATOR || x.typ === CSTParser.KEYWORD
        return CSTParser.str_value(x)
    else
        return join(str_value(a) for a in x)
    end
end

bindingstr(bind::CSTParser.Binding, text::String, pos::Int) = begin
    s = nextind(text, pos - 1)
    e = prevind(text, pos + bind.val.span)
    text[s:e]
end
bindingstr(bind::Nothing, text::String, pos::Int) = ""

# need to keep this consistent with wstype
static_type(bind::CSTParser.Binding) = static_type(bind.val)
function static_type(val::CSTParser.EXPR)
    if CSTParser.defines_function(val)
        "function"
    elseif CSTParser.defines_macro(val)
        "snippet"
    elseif CSTParser.defines_module(val)
        "module"
    elseif CSTParser.defines_struct(val) ||
           CSTParser.defines_abstract(val) ||
           CSTParser.defines_mutable(val) ||
           CSTParser.defines_primitive(val)
        "type"
    else
        "variable"
    end
end

# need to keep this consistent with wsicon
static_icon(bind::CSTParser.Binding) = static_icon(bind.val)
function static_icon(val::CSTParser.EXPR)
    if CSTParser.defines_function(val)
        "λ"
    elseif CSTParser.defines_macro(val)
        "icon-mention"
    elseif CSTParser.defines_module(val)
        "icon-package"
    elseif CSTParser.defines_struct(val) ||
           CSTParser.defines_abstract(val) ||
           CSTParser.defines_mutable(val) ||
           CSTParser.defines_primitive(val)
        "T"
    else
        "v"
    end
end
