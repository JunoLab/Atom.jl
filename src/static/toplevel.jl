#=
Find toplevel items (bind / call)

Downstreams: modules.jl, outline.jl, goto.jl
=#


abstract type ToplevelItem end

struct ToplevelBinding <: ToplevelItem
    expr::EXPR
    bind::Binding
    lines::UnitRange{Int}
end

struct ToplevelCall <: ToplevelItem
    expr::EXPR
    lines::UnitRange{Int}
    verbatim::String
end

struct ToplevelMacroCall <: ToplevelItem
    expr::EXPR
    lines::UnitRange{Int}
    verbatim::String
end

struct ToplevelModuleUsage <: ToplevelItem
    expr::EXPR
    lines::UnitRange{Int}
end

"""
    toplevelitems(text::String; kwargs...)::Vector{ToplevelItem}
    toplevelitems(text::String, expr::EXPR; kwargs...)::Vector{ToplevelItem}

Finds and returns toplevel "item"s (call and binding) in `text`.

keyword arguments:
- `mod::Union{Nothing, String}`: if not `nothing` don't return items within modules
    other than `mod`, otherwise enter into every module.
- `inmod::Bool`: if `true`, don't include toplevel items until it enters into `mod`.
"""
toplevelitems(text::String; kwargs...)::Vector{ToplevelItem} =
    toplevelitems(text, CSTParser.parse(text, true); kwargs...)
function toplevelitems(text::String, expr::EXPR; kwargs...)::Vector{ToplevelItem}
    traverse_expr!(expr)
    return _toplevelitems(text, expr; kwargs...)
end
toplevelitems(text::String, expr::Nothing; kwargs...)::Vector{ToplevelItem} = ToplevelItem[]

function _toplevelitems(
    text::String, expr::EXPR,
    items::Vector{ToplevelItem} = ToplevelItem[], line::Integer = 1, pos::Integer = 1;
    mod::Union{Nothing, String} = nothing, inmod::Bool = false,
)
    # add items if `mod` isn't specified or in a target modle
    if mod === nothing || inmod
        # binding
        bind = bindingof(expr)
        if bind !== nothing
            lines = line:line+counteols_in_expr(expr, text, pos, false)
            push!(items, ToplevelBinding(expr, bind, lines))
        end

        lines = line:line+counteols_in_expr(expr, text, pos, false)

        # destructure multiple returns
        if ismultiplereturn(expr)
            for arg in expr
                (bind = bindingof(arg)) === nothing && continue
                push!(items, ToplevelBinding(arg, bind, lines))
            end
        elseif expr.parent === nothing || !CSTParser.is_assignment(expr.parent)
            # toplevel call
            if iscallexpr(expr)
                push!(items, ToplevelCall(expr, lines, str_value_verbatim(expr, text, pos)))
            # toplevel macro call
            elseif ismacrocall(expr)
                push!(items, ToplevelMacroCall(expr, lines, str_value_verbatim(expr, text, pos)))
            # module usages
            elseif ismoduleusage(expr)
                push!(items, ToplevelModuleUsage(expr, lines))
            end
        end
    end

    if shouldenter(expr, mod)
        # look for more toplevel items in expr:
        if CSTParser.defines_module(expr) && shouldentermodule(expr, mod)
            inmod = true
        end
        for arg in expr
            _toplevelitems(text, arg, items, line, pos; mod = mod, inmod = inmod)
            line += counteols_in_expr(arg, text, pos)
            pos += arg.fullspan
        end
    end
    return items
end

function shouldenter(expr::EXPR, mod::Union{Nothing, String})
    typof(expr) !== CSTParser.Call &&
    !(hasscope(expr) &&
    !(
        typof(expr) === CSTParser.FileH ||
        (CSTParser.defines_module(expr) && shouldentermodule(expr, mod)) ||
        isdoc(expr)
    ))
end

shouldentermodule(expr::EXPR, mod::Nothing) = true
shouldentermodule(expr::EXPR, mod::String) =
    (bind = bindingof(expr)) === nothing ? false : bind.name == mod
