using  Traceur
function lintermessage(warn::Traceur.Warning)
    meth = Traceur.method(warn.call)
    path = Atom.fullpath(string(meth.file))
    line = warn.line < 0 ? meth.line : warn.line
    return Dict(
        "severity" => "warning",
        "provider" => "Traceur",
        "file" => path,
        "range" => [[line-1, 0], [line-1, 99999]],
        "description" => warn.message
    )
end

function showlint(warns)
    @msg staticLint(warns)
end

function clearlint()
    @msg clearLint()
end

function junotrace(f)
    showlint([lintermessage(w) for w in Traceur.warnings(f)])
end

macro trace(ex)
    :(junotrace(() -> $(esc(ex))))
end
