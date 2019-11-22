using CSTParser

#=
utilities
=#

# scope
# -----

function scopeof(expr::CSTParser.EXPR)
    scope = CSTParser.scopeof(expr)
    if scope !== nothing
        return scope
    else
        if expr.typ == CSTParser.Call && expr.parent !== nothing && scopeof(expr.parent) == nothing
            return :call
        end

        if expr.typ == CSTParser.TupleH && expr.parent !== nothing && scopeof(expr.parent) == nothing
            return :tupleh
        end

        if iswhereclause(expr)
            return :where
        end

        if expr.typ == CSTParser.MacroCall
            return :macro
        end

        if expr.typ == CSTParser.Quote
            return :quote
        end
    end
    return nothing
end

# is utilities
# ------------

iscallexpr(expr::CSTParser.EXPR) = expr.typ === CSTParser.Call

ismacrocall(expr::CSTParser.EXPR) = expr.typ === CSTParser.MacroCall

function isinclude(expr::CSTParser.EXPR)
    iscallexpr(expr) &&
        length(expr) === 4 &&
        expr.args[1].val == "include" &&
        expr.args[3].val isa String &&
        endswith(expr.args[3].val, ".jl")
end

ismodule(expr::CSTParser.EXPR) =
    expr.typ === CSTParser.ModuleH || expr.typ === CSTParser.BareModule

function isdoc(expr::CSTParser.EXPR)
    ismacrocall(expr) &&
        length(expr) >= 1 &&
        (
            expr.args[1].typ === CSTParser.GlobalRefDoc ||
            str_value(expr.args[1]) == "@doc"
        )
end

function ismultiplereturn(expr::CSTParser.EXPR)
    expr.typ === CSTParser.TupleH &&
        expr.args !== nothing &&
        !isempty(filter(a -> CSTParser.bindingof(a) !== nothing, expr.args))
end

function iswhereclause(expr::CSTParser.EXPR)
    expr.typ === CSTParser.WhereOpCall &&
        expr.parent !== nothing &&
        expr.args !== nothing
end

function isconstexpr(expr::CSTParser.EXPR)
    (parent = CSTParser.parentof(expr)) !== nothing &&
        parent.typ === CSTParser.Const
end

ismoduleusage(expr::CSTParser.EXPR) = isimport(expr) || isexport(expr)
isimport(expr::CSTParser.EXPR) = expr.typ === CSTParser.Import || expr.typ === CSTParser.Using
isexport(expr::CSTParser.EXPR) = expr.typ === CSTParser.Export

# string utilities
# ----------------

function Base.countlines(expr::CSTParser.EXPR, text::String, pos::Int, full::Bool = true; eol = '\n')
    endpos = pos + (full ? expr.fullspan : expr.span)
    n = ncodeunits(text)
    s = nextind(text, clamp(pos - 1, 0, n))
    e = prevind(text, clamp(endpos, 1, n + 1))
    count(c -> c === eol, text[s:e])
end

"""
    str_value(x::CSTParser.EXPR)

Reconstruct source code from a `CSTParser.EXPR`.

Adapted from https://github.com/julia-vscode/DocumentFormat.jl/blob/b7e22ca47254007b5e7dd3c678ba27d8744d1b1f/src/passes.jl#L108.
"""
function str_value(x::CSTParser.EXPR)
    if x.typ === CSTParser.PUNCTUATION
        x.kind == CSTParser.Tokens.LPAREN && return "("
        x.kind == CSTParser.Tokens.LBRACE && return "{"
        x.kind == CSTParser.Tokens.LSQUARE && return "["
        x.kind == CSTParser.Tokens.RPAREN && return ")"
        x.kind == CSTParser.Tokens.RBRACE && return "}"
        x.kind == CSTParser.Tokens.RSQUARE && return "]"
        x.kind == CSTParser.Tokens.COMMA && return ", "
        x.kind == CSTParser.Tokens.SEMICOLON && return ";"
        x.kind == CSTParser.Tokens.AT_SIGN && return "@"
        x.kind == CSTParser.Tokens.DOT && return "."
        return ""
    elseif x.kind === CSTParser.Tokens.TRIPLE_STRING
        return string("\"\"\"", x.val, "\"\"\"")
    elseif x.kind === CSTParser.Tokens.STRING
        return string("\"", x.val, "\"")
    elseif x.kind === CSTParser.Tokens.EQ
        return " = "
    elseif x.kind === CSTParser.Tokens.WHERE
        return " where "
    elseif x.typ === CSTParser.Parameters
        return "; " * join(str_value(a) for a in x)
    elseif x.typ === CSTParser.IDENTIFIER || x.typ === CSTParser.LITERAL || x.typ === CSTParser.OPERATOR || x.typ === CSTParser.KEYWORD
        return CSTParser.str_value(x)
    elseif x.typ === CSTParser.Using
        "using " * join(str_value(a) for a in x)
    elseif x.typ === CSTParser.Import
        "import " * join(str_value(a) for a in x)
    elseif x.typ === CSTParser.Export
        "export " * join(str_value(a) for a in x)
    else
        return join(str_value(a) for a in x)
    end
end

"""
    str_value_as_is(expr::CSTParser.EXPR, text::String, pos::Int)

Extract `expr`'s source from `text`, starting at `pos`. Similar to `str_value`, but doesn't
*reconstruct* the source code.
"""
function str_value_as_is(expr::CSTParser.EXPR, text::String, pos::Int)
    endpos = pos + expr.span
    n = ncodeunits(text)
    s = nextind(text, clamp(pos - 1, 0, n))
    e = prevind(text, clamp(endpos, 1, n + 1))
    strip(text[s:e])
end
str_value_as_is(bind::CSTParser.Binding, text::String, pos::Int) = str_value_as_is(bind.val, text, pos)
str_value_as_is(bind, text::String, pos::Int) = ""

# atom icon & types
# -----------------
# NOTE: need to keep this consistent with wstype/wsicon

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
        isconstexpr(val) ? "constant" : "variable"
    end
end

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
        isconstexpr(val) ? "c" : "v"
    end
end


include("toplevel.jl")
include("local.jl")
