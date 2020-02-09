#=
Scope information for `EXRR`.

NOTE:
- StaticLint.jl adds various scope-related information for `EXPR.meta.scope` field,
    but we currently just need to know whether `EXPR` introduces a scope or not.
    So let's just make a function to check that, and don't fill `EXPR` with scope information.
- Adapted from https://github.com/julia-vscode/StaticLint.jl/blob/cd8935a138caf18385c46db977b52c5ac9e90809/src/scope.jl
=#

function hasscope(x::EXPR)
    t = typof(x)

    # NOTE: added conditions below when adapted
    if t === CSTParser.TupleH && (p = parentof(x)) !== nothing && !hasscope(p)
        return true
    elseif iswhereclause(x)
        return true
    elseif t === CSTParser.MacroCall
        return true
    elseif t === CSTParser.Quote
        return true
    # NOTE: end

    elseif t === CSTParser.BinaryOpCall
        k = kindof(x.args[2])
        if k === Tokens.EQ && CSTParser.is_func_call(x.args[1])
            return true
        elseif k === Tokens.EQ && typof(x.args[1]) === CSTParser.Curly
            return true
        elseif k === Tokens.ANON_FUNC
            return true
        else
            return false
        end
    # # NOTE: commented out when adapted
    # elseif t === CSTParser.WhereOpCall
    #     # unless in func def signature
    #     return !_in_func_def(x)
    elseif t === CSTParser.FunctionDef ||
           t === CSTParser.Macro ||
           t === CSTParser.For ||
           t === CSTParser.While ||
           t === CSTParser.Let ||
           t === CSTParser.Generator || # and Flatten?
           t === CSTParser.Try ||
           t === CSTParser.Do ||
           t === CSTParser.ModuleH ||
           t === CSTParser.BareModule ||
           t === CSTParser.Abstract ||
           t === CSTParser.Primitive ||
           t === CSTParser.Mutable ||
           t === CSTParser.Struct
        return true
    end

    return false
end

# # NOTE: commented out when adapted
# # only called in WhereOpCall
# function _in_func_def(x::EXPR)
#     # check 1st arg contains a call (or op call)
#     ex = x.args[1]
#     while true
#         if typof(ex) === CSTParser.WhereOpCall ||
#            (
#             typof(ex) === CSTParser.BinaryOpCall &&
#             kindof(ex.args[2]) === CSTParser.Tokens.DECLARATION
#            )
#             ex = ex.args[1]
#         elseif typof(ex) === CSTParser.Call ||
#                (
#                 typof(ex) === CSTParser.BinaryOpCall &&
#                 !(kindof(ex.args[2]) === CSTParser.Tokens.DOT)
#                ) ||
#                typof(ex) == CSTParser.UnaryOpCall #&& kindof(ex.args[1]) == CSTParser.Tokens.MINUS
#             break
#         else
#             return false
#         end
#     end
#     # check parent is func def
#     ex = x
#     while true
#         if !(parentof(ex) isa EXPR)
#             return false
#         elseif typof(parentof(ex)) === CSTParser.WhereOpCall ||
#                typof(parentof(ex)) === CSTParser.InvisBrackets
#             ex = parentof(ex)
#         elseif typof(parentof(ex)) === CSTParser.FunctionDef ||
#                (
#                 typof(parentof(ex)) === CSTParser.BinaryOpCall &&
#                 kindof(parentof(ex).args[2]) === CSTParser.Tokens.EQ
#                )
#             return true
#         else
#             return false
#         end
#     end
#     return false
# end
