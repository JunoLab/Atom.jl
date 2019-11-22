handle("updateeditor") do data
    @destruct [
        text || "",
        mod || "Main",
        path || nothing,
        updateSymbols || true
    ] = data

    try
        updateeditor(text, mod, path, updateSymbols)
    catch err
        []
    end
end

# NOTE: update outline and symbols cache all in one go
function updateeditor(text, mod = "Main", path = nothing, updateSymbols = true)
    # update symbols cache
    # ref: https://github.com/JunoLab/Juno.jl/issues/407
    updateSymbols && updatesymbols(mod, path, text)

    # return outline
    outline(toplevelitems(text))
end

function outline(items)
    filter!(map(outlineitem, items)) do item
        item !== nothing
    end
end

function outlineitem(binding::ToplevelBinding)
    expr = binding.expr
    bind = binding.bind
    lines = binding.lines

    name = bind.name
    if CSTParser.has_sig(expr)
        name = str_value(CSTParser.get_sig(expr))
    end
    type = static_type(bind)
    icon = static_icon(bind)
    Dict(
        :name  => name,
        :type  => type,
        :icon  => icon,
        :lines => [first(lines), last(lines)]
    )
end
function outlineitem(call::ToplevelCall)
    expr = call.expr
    lines = call.lines

    # don't show doc strings
    isdoc(expr) && return nothing

    # show first line verbatim of macro calls
    if ismacrocall(expr)
        return Dict(
            :name  => strlimit(first(split(call.callstr, '\n')), 100),
            :type  => "snippet",
            :icon  => "icon-mention",
            :lines => [first(lines), last(lines)],
        )
    end

    # show includes
    if isinclude(expr)
        return Dict(
            :name  => call.callstr,
            :type  => "module",
            :icon  => "icon-file-code",
            :lines => [first(lines), last(lines)],
        )
    end

    return nothing
end
