#=
Binding information for `EXPR`.

NOTE:
- Since we only want really basic information about `EXPR`, let's just add binding information
    for `EXPR.meta` field for now.
- Adapted from https://github.com/julia-vscode/StaticLint.jl/blob/619d2d7138e921e5748db32002051666ef2d54f0/src/bindings.jl
=#

struct Binding
    name::String
    val::Union{Binding,EXPR,Nothing}
    # NOTE: omitted: type, refs, prev, next
end
function Binding(expr::EXPR, val::Union{Binding,EXPR,Nothing})
    ex = CSTParser.get_name(expr)
    name = if (name = valof(ex)) === nothing
        typof(ex) === CSTParser.OPERATOR ? str_value(ex) : ""
    else
        name
    end
    return Binding(name, val)
end
Binding(expr::EXPR) = Binding(expr, expr)

Base.show(io::IO, bind::Binding) = printstyled(io, ' ', "Binding(", bind.name, ')'; color = :blue)

hasbinding(expr::EXPR) = expr.meta isa Binding
bindingof(expr::EXPR)::Union{Nothing,Binding} = hasbinding(expr) ? expr.meta : nothing

# adapted from https://github.com/julia-vscode/StaticLint.jl/blob/3a24e4b84a419ea607aaa51e42b3b45d172438c8/src/StaticLint.jl#L78-L113
"""
    traverse_expr!(x::EXPR)

Iterates across the child nodes of an `EXPR` in execution order calling
  [`mark_bindings`](@ref) on each node.
"""
function traverse_expr!(x::EXPR)
    mark_bindings!(x)

    if typof(x) === CSTParser.BinaryOpCall &&
       (
        CSTParser.is_assignment(x) && !CSTParser.is_func_call(x.args[1]) ||
        typof(x.args[2]) === CSTParser.Tokens.DECLARATION
       ) &&
       !(CSTParser.is_assignment(x) && typof(x.args[1]) === CSTParser.Curly)
        traverse_expr!(x.args[3])
        traverse_expr!(x.args[2])
        traverse_expr!(x.args[1])
    elseif typof(x) === CSTParser.WhereOpCall
        @inbounds for i = 3:length(x.args)
            traverse_expr!(x.args[i])
        end
        traverse_expr!(x.args[1])
        traverse_expr!(x.args[2])
    elseif typof(x) === CSTParser.Generator
        @inbounds for i = 2:length(x.args)
            traverse_expr!(x.args[i])
        end
        traverse_expr!(x.args[1])
    elseif typof(x) === CSTParser.Flatten &&
           x.args !== nothing && length(x.args) === 1 &&
           x.args[1].args !== nothing &&
           length(x.args[1]) >= 3 && length(x.args[1].args[1]) >= 3
        for i = 3:length(x.args[1].args[1].args)
            traverse_expr!(x.args[1].args[1].args[i])
        end
        for i = 3:length(x.args[1].args)
            traverse_expr!(x.args[1].args[i])
        end
        traverse_expr!(x.args[1].args[1].args[1])
    elseif x.args !== nothing
        @inbounds for i = 1:length(x.args)
            traverse_expr!(x.args[i])
        end
    end
end

function mark_bindings!(x::EXPR)
    hasbinding(x) && return

    if typof(x) === CSTParser.BinaryOpCall
        if kindof(x.args[2]) === CSTParser.Tokens.EQ
            if CSTParser.is_func_call(x.args[1])
                mark_binding!(x)
                mark_sig_args!(x.args[1])
            elseif typof(x.args[1]) === CSTParser.Curly
                mark_typealias_bindings!(x)
            else
                mark_binding!(x.args[1], x)
            end
        elseif kindof(x.args[2]) === CSTParser.Tokens.ANON_FUNC
            mark_binding!(x.args[1], x)
        end
    elseif typof(x) === CSTParser.WhereOpCall
        for i = 3:length(x.args)
            typof(x.args[i]) === CSTParser.PUNCTUATION && continue
            mark_binding!(x.args[i])
        end
    elseif typof(x) === CSTParser.For
        markiterbinding!(x.args[2])
    elseif typof(x) === CSTParser.Generator
        for i = 3:length(x.args)
            typof(x.args[i]) === CSTParser.PUNCTUATION && continue
            markiterbinding!(x.args[i])
        end
    elseif typof(x) === CSTParser.Filter
        for i = 1:length(x.args)-2
            typof(x.args[i]) === CSTParser.PUNCTUATION && continue
            markiterbinding!(x.args[i])
        end
    elseif typof(x) === CSTParser.Do
        if typof(x.args[3]) === CSTParser.TupleH
            for i = 1:length(x.args[3].args)
                typof(x.args[3].args[i]) === CSTParser.PUNCTUATION && continue
                mark_binding!(x.args[3].args[i])
            end
        end
        # markiterbinding!(x.args[3])
    elseif typof(x) === CSTParser.FunctionDef
        name = CSTParser.get_name(x)
        # mark external binding
        x.meta = Binding(name, x)
        mark_sig_args!(CSTParser.get_sig(x))
    elseif typof(x) === CSTParser.ModuleH || typof(x) === CSTParser.BareModule
        x.meta = Binding(x.args[2], x)
    elseif typof(x) === CSTParser.Macro
        name = CSTParser.get_name(x)
        x.meta = Binding(name, x)
        mark_sig_args!(CSTParser.get_sig(x))
    elseif typof(x) === CSTParser.Try && length(x.args) > 3
        mark_binding!(x.args[4])
    elseif typof(x) === CSTParser.Abstract || typof(x) === CSTParser.Primitive
        name = CSTParser.get_name(x)
        x.meta = Binding(name, x)
        mark_parameters(CSTParser.get_sig(x))
    elseif typof(x) === CSTParser.Mutable || typof(x) === CSTParser.Struct
        name = CSTParser.get_name(x)
        x.meta = Binding(name, x)
        mark_parameters(CSTParser.get_sig(x))
        blocki = typof(x.args[3]) === CSTParser.Block ? 3 : 4
        for i = 1:length(x.args[blocki])
            CSTParser.defines_function(x.args[blocki].args[i]) && continue
            mark_binding!(x.args[blocki].args[i])
        end
    elseif typof(x) === CSTParser.Local
        if length(x.args) == 2
            if typof(x.args[2]) === CSTParser.IDENTIFIER
                mark_binding!(x.args[2])
            elseif typof(x.args[2]) === CSTParser.TupleH
                for i = 1:length(x.args[2].args)
                    if typof(x.args[2].args[i]) === CSTParser.IDENTIFIER
                        mark_binding!(x.args[2].args[i])
                    end
                end
            end
        end
    end
end

function mark_binding!(x::EXPR, val = x)
    if typof(x) === CSTParser.Kw
        mark_binding!(x.args[1], x)
    elseif typof(x) === CSTParser.TupleH || typof(x) === CSTParser.Parameters
        for arg in x.args
            typof(arg) === CSTParser.PUNCTUATION && continue
            mark_binding!(arg, val)
        end
    elseif typof(x) === CSTParser.BinaryOpCall &&
           kindof(x.args[2]) === CSTParser.Tokens.DECLARATION &&
           typof(x.args[1]) === CSTParser.TupleH
        mark_binding!(x.args[1], x)
    elseif typof(x) === CSTParser.InvisBrackets
        mark_binding!(CSTParser.rem_invis(x), val)
    elseif typof(x) === CSTParser.UnaryOpCall &&
           kindof(x.args[1]) === CSTParser.Tokens.DECLARATION
        return x
    elseif typof(x) === CSTParser.Ref
        # https://github.com/JunoLab/Juno.jl/issues/502
        return x
    else# if typof(x) === IDENTIFIER || (typof(x) === BinaryOpCall && kindof(x.args[2]) === CSTParser.Tokens.DECLARATION)
        x.meta = Binding(CSTParser.get_name(x), val)
    end
    return x
end

function mark_parameters(sig::EXPR)
    signame = CSTParser.rem_where_subtype(sig)
    if typof(signame) === CSTParser.Curly
        for i = 3:length(signame.args)-1
            if typof(signame.args[i]) !== CSTParser.PUNCTUATION
                mark_binding!(signame.args[i])
            end
        end
    end
    return sig
end

function markiterbinding!(iter::EXPR)
    if typof(iter) === CSTParser.BinaryOpCall &&
       kindof(iter.args[2]) in (CSTParser.Tokens.EQ, CSTParser.Tokens.IN, CSTParser.Tokens.ELEMENT_OF)
        mark_binding!(iter.args[1], iter)
    elseif typof(iter) === CSTParser.Block
        for i = 1:length(iter.args)
            typof(iter.args[i]) === CSTParser.PUNCTUATION && continue
            markiterbinding!(iter.args[i])
        end
    end
    return iter
end

function mark_sig_args!(x::EXPR)
    if typof(x) === CSTParser.Call || typof(x) === CSTParser.TupleH
        if typof(x.args[1]) === CSTParser.InvisBrackets &&
           typof(x.args[1].args[2]) === CSTParser.BinaryOpCall &&
           kindof(x.args[1].args[2].args[2]) === CSTParser.Tokens.DECLARATION
            mark_binding!(x.args[1].args[2])
        end
        for i = 2:length(x.args)-1
            a = x.args[i]
            if typof(a) === CSTParser.Parameters
                for j = 1:length(a.args)
                    aa = a.args[j]
                    if !(typof(aa) === CSTParser.PUNCTUATION)
                        mark_binding!(aa)
                    end
                end
            elseif !(typof(a) === CSTParser.PUNCTUATION)
                mark_binding!(a)
            end
        end
    elseif typof(x) === CSTParser.WhereOpCall
        for i = 3:length(x.args)
            if !(typof(x.args[i]) === CSTParser.PUNCTUATION)
                mark_binding!(x.args[i])
            end
        end
        mark_sig_args!(x.args[1])
    elseif typof(x) === CSTParser.BinaryOpCall
        if kindof(x.args[2]) == CSTParser.Tokens.DECLARATION
            mark_sig_args!(x.args[1])
        else
            mark_binding!(x.args[1])
            mark_binding!(x.args[3])
        end
    elseif typof(x) == CSTParser.UnaryOpCall && typof(x.args[2]) == CSTParser.InvisBrackets
        mark_binding!(x.args[2].args[2])
    end
end

function mark_typealias_bindings!(x::EXPR)
    mark_binding!(x, x)
    for i = 2:length(x.args[1].args)
        if typof(x.args[1].args[i]) === CSTParser.IDENTIFIER
            mark_binding!(x.args[1].args[i])
        elseif typof(x.args[1].args[i]) === CSTParser.BinaryOpCall &&
               kindof(x.args[1].args[i].args[2]) === CSTParser.Tokens.ISSUBTYPE &&
               typof(x.args[1].args[i].args[1]) === CSTParser.IDENTIFIER
            mark_binding!(x.args[1].args[i].args[1])
        end
    end
    return x
end
