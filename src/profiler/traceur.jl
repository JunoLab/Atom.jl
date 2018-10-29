import Traceur

macro trace(ex)
    :(showtrace(gettrace(() -> $(esc(ex)))))
end

function gettrace(f)
    warns = []
    Traceur.trace(x -> push!(warns, transformwarn(x)), f)
    warns
end

function transformwarn(w)
    meth = Traceur.method(w.call)
    file, path = expandpath(String(meth.file))
    line = max(0, w.line - 1)

    return Dict(:file => file,
                :realpath => path,
                :description => w.message,
                :range => [[line, 0], [line, 999]],
                :provider => "Traceur",
                :severity => "Warning")
end

function showtrace(trace)
    Atom.msg("staticLint", trace)
end
