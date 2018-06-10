using MacroTools

macro cw(ex)
    fex = string(ex)
    @capture(ex, f_(xs__))
    @esc(f, xs, ex)
    quote
        io = IOBuffer()
        code_warntype(io, $f, (typeof.($xs)...,))

        strs = String.(split(String(take!(io)), '\n'))

        lines = Vector[]

        nextline = nothing
        for (i, str) in enumerate(strs)
            line = match(r"# line (\d+)\:", str)
            if nextline ≠ nothing
                push!(lines, [nextline, Atom.removeansi(str)])
                nextline = nothing
            else
                push!(lines, ["", Atom.removeansi(str)])
            end
            if line ≠ nothing
                nextline = line[1]
                continue
            end
        end
        Atom.msg("showCompiled", "$($fex)", "@code_warntype for $($fex):" , lines)
    end
end
