#=
Test whether binding markings works correctly.

Adapted from https://github.com/julia-vscode/CSTParser.jl/blob/e4e32477a1e7b4d57652b3755659f169b50fb60e/test/bindings.jl
=#

using Atom: traverse_expr!, bindingof
using CSTParser
using CSTParser: typof

function collect_bindings(ex)
    traverse_expr!(ex)
    return _collect_bindings(ex)
end
function _collect_bindings(x, out = String[])
    if bindingof(x) !== nothing
        push!(out, bindingof(x).name)
    end
    if (typof(x) === CSTParser.BinaryOpCall && CSTParser.is_assignment(x) && !CSTParser.is_func_call(x)) || typof(x) === CSTParser.Filter
        _collect_bindings(x.args[3], out)
        _collect_bindings(x.args[2], out)
        _collect_bindings(x.args[1], out)
    elseif typof(x) === CSTParser.WhereOpCall
        @inbounds for i = 3:length(x.args)
            _collect_bindings(x.args[i], out)
        end
        _collect_bindings(x.args[1], out)
        _collect_bindings(x.args[2], out)
    elseif typof(x) === CSTParser.Generator
        @inbounds for i = 2:length(x.args)
            _collect_bindings(x.args[i], out)
        end
        _collect_bindings(x.args[1], out)
    elseif x.args === nothing
    else
        @inbounds for a in x.args
            _collect_bindings(a, out)
        end
    end
    return out
end

@test collect_bindings(CSTParser.parse("x = 1")) == ["x"]
@test collect_bindings(CSTParser.parse("(x) = 1")) == ["x"]
@test collect_bindings(CSTParser.parse("x, y =  1")) == ["x", "y"]
@test collect_bindings(CSTParser.parse("(x, y) =  1")) == ["x", "y"]
@test collect_bindings(CSTParser.parse("x = y =  1")) == ["y", "x"]
@test collect_bindings(CSTParser.parse("x::T = 1")) == ["x"]

@test collect_bindings(CSTParser.parse("f() = x")) == ["f"]
@test collect_bindings(CSTParser.parse("f(a) = x")) == ["f", "a"]
@test collect_bindings(CSTParser.parse("f(a) = x")) == ["f", "a"]
@test collect_bindings(CSTParser.parse("f(x::T) where {T <: S} where R = x")) == ["f", "R", "T","x"]
@test collect_bindings(CSTParser.parse("function f end")) == ["f"]
@test collect_bindings(CSTParser.parse("function f() end")) == ["f"]
@test collect_bindings(CSTParser.parse("function f() where T end")) == ["f", "T"]

@test collect_bindings(CSTParser.parse("macro m end")) == ["m"]
@test collect_bindings(CSTParser.parse("macro m() end")) == ["m"]

@test collect_bindings(CSTParser.parse("abstract type T end")) == ["T"]
@test collect_bindings(CSTParser.parse("abstract type T <: S end")) == ["T"]
@test collect_bindings(CSTParser.parse("abstract type T{S} end")) == ["T", "S"]

@test collect_bindings(CSTParser.parse("primitive type T 4 end")) == ["T"]
@test collect_bindings(CSTParser.parse("primitive type T <: S 4 end")) == ["T"]
@test collect_bindings(CSTParser.parse("primitive type T{S} 4 end")) == ["T", "S"]

@test collect_bindings(CSTParser.parse("struct T end")) == ["T"]
@test collect_bindings(CSTParser.parse("struct T <: S end")) == ["T"]
@test collect_bindings(CSTParser.parse("struct T{S} end")) == ["T" ,"S"]
@test collect_bindings(CSTParser.parse("struct T\nx end")) == ["T", "x"]
@test collect_bindings(CSTParser.parse("struct T\nT() = new()\n end")) == ["T", "T"]

@test collect_bindings(CSTParser.parse("mutable struct T end")) == ["T"]

@test collect_bindings(CSTParser.parse("for i = 1 end")) == ["i"]
@test collect_bindings(CSTParser.parse("let i = 1 end")) == ["i"]
@test collect_bindings(CSTParser.parse("[i for i = 1]")) == ["i"]
@test collect_bindings(CSTParser.parse("[i for i in 1]")) == ["i"]
@test collect_bindings(CSTParser.parse("try catch e end")) == ["e"]
@test collect_bindings(CSTParser.parse("map() do x end")) == ["x"]

@test collect_bindings(CSTParser.parse("(a,b)->x")) == ["a", "b"]
collect_bindings(CSTParser.parse("function f(a::T = 1) end")) == ["f", "a"]

let cst = CSTParser.parse("function a::T * b::T end")
    traverse_expr!(cst)
    @test bindingof(cst[2][1]) !== nothing
    @test bindingof(cst[2][3]) !== nothing
end

@test collect_bindings(CSTParser.parse("-(x::T) = x")) == ["-", "x"]

# https://github.com/JunoLab/Juno.jl/issues/502
@test isempty(collect_bindings(CSTParser.parse("ary[ind] = rand(Int)")))
