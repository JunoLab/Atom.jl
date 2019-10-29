#=
Find toplevel items (bind / call)

- downstreams: modules.jl, outline.jl, goto.jl
- TODO: crate `ToplevelScope` and allow to escape modules
=#


abstract type ToplevelItem end

struct ToplevelBinding <: ToplevelItem
    expr::CSTParser.EXPR
    bind::CSTParser.Binding
    lines::UnitRange{Int}
end

struct ToplevelCall <: ToplevelItem
    expr::CSTParser.EXPR
    lines::UnitRange{Int}
    callstr::String
end

struct ToplevelTupleH <: ToplevelItem
    expr::CSTParser.EXPR
    lines::UnitRange{Int}
end

function toplevelitems(expr, text, items::Vector{ToplevelItem} = Vector{ToplevelItem}(), line = 1, pos = 1)
    # binding
    bind = CSTParser.bindingof(expr)
    if bind !== nothing
        lines = line:line+countlines(expr, text, pos, false)
        push!(items, ToplevelBinding(expr, bind, lines))
    end

    lines = line:line+countlines(expr, text, pos, false)

    # toplevel call
    if iscallexpr(expr)
        push!(items, ToplevelCall(expr, lines, str_value_as_is(expr, text, pos)))
    end

    # destructure multiple returns
    ismultiplereturn(expr) && push!(items, ToplevelTupleH(expr, lines))

    # look for more toplevel items in expr:
    if shouldenter(expr)
        if expr.args !== nothing
            for arg in expr.args
                toplevelitems(arg, text, items, line, pos)
                line += countlines(arg, text, pos)
                pos += arg.fullspan
            end
        end
    end
    return items
end

function shouldenter(expr::CSTParser.EXPR)
    !(scopeof(expr) !== nothing && !(
        expr.typ === CSTParser.FileH ||
        expr.typ === CSTParser.ModuleH ||
        expr.typ === CSTParser.BareModule ||
        isdoc(expr)
    ))
end
