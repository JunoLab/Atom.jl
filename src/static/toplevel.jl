#=
Find toplevel items (bind / call)

- downstreams: modules.jl, outline.jl, goto.jl
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
    str::String
end

struct ToplevelMacroCall <: ToplevelItem
    expr::EXPR
    lines::UnitRange{Int}
    str::String
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
toplevelitems(text::String; kwargs...) = toplevelitems(text, CSTParser.parse(text, true); kwargs...)
function toplevelitems(text::String, expr::EXPR; kwargs...)
    traverse_expr!(expr)
    return _toplevelitems(text, expr; kwargs...)
end
toplevelitems(text::String, expr::Nothing; kwargs...) = ToplevelItem[]

function _toplevelitems(
    text::String, expr::EXPR,
    items::Vector{ToplevelItem} = ToplevelItem[], line::Int = 1, pos::Int = 1;
    mod::Union{Nothing, String} = nothing, inmod::Bool = false,
)
    # add items if `mod` isn't specified or in a target modle
    if mod === nothing || inmod
        # binding
        bind = bindingof(expr)
        if bind !== nothing
            lines = line:line+countlines(expr, text, pos, false)
            push!(items, ToplevelBinding(expr, bind, lines))
        end

        lines = line:line+countlines(expr, text, pos, false)

        # destructure multiple returns
        if ismultiplereturn(expr)
            for arg in expr
                (bind = bindingof(arg)) === nothing && continue
                push!(items, ToplevelBinding(arg, bind, lines))
            end
        # toplevel call
        elseif iscallexpr(expr)
            push!(items, ToplevelCall(expr, lines, str_value_as_is(expr, text, pos)))
        # toplevel macro call
        elseif ismacrocall(expr)
            push!(items, ToplevelMacroCall(expr, lines, str_value_as_is(expr, text, pos)))
        # module usages
        elseif ismoduleusage(expr)
            push!(items, ToplevelModuleUsage(expr, lines))
        end
    end

    # look for more toplevel items in expr:
    if shouldenter(expr, mod)
        if CSTParser.defines_module(expr) && shouldentermodule(expr, mod)
            inmod = true
        end
        for arg in expr
            _toplevelitems(text, arg, items, line, pos; mod = mod, inmod = inmod)
            line += countlines(arg, text, pos)
            pos += arg.fullspan
        end
    end
    return items
end

function shouldenter(expr::EXPR, mod::Union{Nothing, String})
    !(hasscope(expr) && !(
        expr.typ === CSTParser.FileH ||
        (CSTParser.defines_module(expr) && shouldentermodule(expr, mod)) ||
        isdoc(expr)
    ))
end

shouldentermodule(expr::EXPR, mod::Nothing) = true
shouldentermodule(expr::EXPR, mod::String) =
    (bind = bindingof(expr)) === nothing ? false : bind.name == mod
