using CSTParser
using CSTParser.Tokens
using CSTParser: EXPR, typof, kindof, valof, parentof

# meta information
# ----------------

include("bindings.jl")
include("scope.jl")

# toplevel / local
# ----------------

include("toplevel.jl")
include("local.jl")

# is utilities
# ------------

iscallexpr(expr::EXPR) = typof(expr) === CSTParser.Call

ismacrocall(expr::EXPR) = typof(expr) === CSTParser.MacroCall

function isinclude(expr::EXPR)
    @inbounds iscallexpr(expr) &&
        length(expr) === 4 &&
        valof(expr.args[1]) == "include" &&
        (filename = valof(expr.args[3])) isa String &&
        endswith(filename, ".jl")
end

function isprecompile(expr::EXPR)
    @inbounds iscallexpr(expr) &&
        length(expr) >= 1 &&
        valof(expr.args[1]) == "__precompile__"
end

function isdoc(expr::EXPR)
    @inbounds ismacrocall(expr) &&
        length(expr) >= 1 &&
        (typof(expr.args[1]) === CSTParser.GlobalRefDoc || str_value(expr.args[1]) == "@doc")
end

function ismultiplereturn(expr::EXPR)
    typof(expr) === CSTParser.TupleH &&
        expr.args !== nothing &&
        !isempty(filter(a -> bindingof(a) !== nothing, expr.args))
end

function iswhereclause(expr::EXPR)
    typof(expr) === CSTParser.WhereOpCall &&
        parentof(expr) !== nothing &&
        expr.args !== nothing
end

function isconstexpr(expr::EXPR)
    (parent = parentof(expr)) !== nothing && typof(parent) === CSTParser.Const
end

ismoduleusage(expr::EXPR) = isimport(expr) || isexport(expr)
isimport(expr::EXPR) = (t = typof(expr)) === CSTParser.Import || t === CSTParser.Using
isexport(expr::EXPR) = typof(expr) === CSTParser.Export

# string utilities
# ----------------

function counteols_in_expr(expr::EXPR, text::String, pos::Integer, full::Bool = true; eol = '\n')
    endpos = pos + (full ? expr.fullspan : expr.span)
    n = ncodeunits(text)
    s = nextind(text, clamp(pos - 1, 0, n))
    e = prevind(text, clamp(endpos, 1, n + 1))
    count(c -> c === eol, text[s:e])
end

# adapted from https://github.com/julia-vscode/DocumentFormat.jl/blob/90c35540f48330fe1453c5ac1a62d8bc5df017b7/src/passes.jl#L112-L134
"""
    str_value(x::EXPR)::String

_Reconstruct_ a source code from `x`.
"""
function str_value(x::EXPR)::String
    t = typof(x)
    k = kindof(x)
    if t === CSTParser.PUNCTUATION
        k === Tokens.LPAREN && return "("
        k === Tokens.LBRACE && return "{"
        k === Tokens.LSQUARE && return "["
        k === Tokens.RPAREN && return ")"
        k === Tokens.RBRACE && return "}"
        k === Tokens.RSQUARE && return "]"
        k === Tokens.COMMA && return ", "
        k === Tokens.SEMICOLON && return ";"
        k === Tokens.AT_SIGN && return "@"
        k === Tokens.DOT && return "."
        return ""
    elseif k === Tokens.TRIPLE_STRING
        return string("\"\"\"", valof(x), "\"\"\"")
    elseif k === Tokens.STRING
        return string("\"", x.val, "\"")
    elseif k === Tokens.EQ
        return " = "
    elseif k === Tokens.WHERE
        return " where "
    elseif t === CSTParser.Parameters
        return "; " * join(str_value(a) for a in x)
    elseif t === CSTParser.IDENTIFIER || t === CSTParser.LITERAL || t === CSTParser.OPERATOR || t === CSTParser.KEYWORD
        return CSTParser.str_value(x)
    elseif t === CSTParser.Using
        return "using " * join(str_value(a) for a in x)
    elseif t === CSTParser.Import
        return "import " * join(str_value(a) for a in x)
    elseif t === CSTParser.Export
        return "export " * join(str_value(a) for a in x)
    else
        return join(str_value(a) for a in x)
    end
end

"""
    str_value_verbatim(expr::EXPR, text::AbstractString, pos::Integer)
    str_value_verbatim(bind::Binding, text::AbstractString, pos::Integer)

_Extract_ a source code from `text` that corresponds to `expr` starting from `pos`.
"""
function str_value_verbatim(expr::EXPR, text::AbstractString, pos::Integer)
    endpos = pos + expr.span
    n = ncodeunits(text)
    s = nextind(text, clamp(pos - 1, 0, n))
    e = prevind(text, clamp(endpos, 1, n + 1))
    return string(strip(text[s:e]))
end
str_value_verbatim(bind::Binding, text::AbstractString, pos::Integer) = str_value_verbatim(bind.val, text, pos)
str_value_verbatim(bind, text::AbstractString, pos::Integer) = ""

# atom icon & types
# -----------------
# NOTE: need to keep this consistent with wstype/wsicon

static_type(bind::Binding) = static_type(bind.val)
static_type(bind::ActualLocalBinding) = static_type(bind.expr)
function static_type(val::EXPR)
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

static_icon(bind::Binding) = static_icon(bind.val)
static_icon(bind::ActualLocalBinding) = static_icon(bind.expr)
function static_icon(val::EXPR)
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
