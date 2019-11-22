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

outline(items) = filter!(item -> item !== nothing, outlineitem.(items))

outlineitem(item::ToplevelItem) = nothing # fallback case
outlineitem(binding::ToplevelBinding) = begin
    expr = binding.expr
    bind = binding.bind
    name = CSTParser.has_sig(expr) ? str_value(CSTParser.get_sig(expr)) : bind.name
    Dict(
        :name  => name,
        :type  => static_type(bind),
        :icon  => static_icon(bind),
        :lines => [first(binding.lines), last(binding.lines)]
    )
end
outlineitem(call::ToplevelCall) = begin
    # show includes
    isinclude(call.expr) && return Dict(
        :name  => call.str,
        :type  => "module",
        :icon  => "icon-file-code",
        :lines => [first(call.lines), last(call.lines)],
    )

    nothing
end
outlineitem(macrocall::ToplevelMacroCall) = begin
    # don't show doc strings
    isdoc(macrocall.expr) && return nothing

    # show first line verbatim of macro calls
    Dict(
        :name  => strlimit(first(split(macrocall.str, '\n')), 100),
        :type  => "snippet",
        :icon  => "icon-mention",
        :lines => [first(macrocall.lines), last(macrocall.lines)],
    )
end
outlineitem(usage::ToplevelModuleUsage) = begin
    Dict(
        :name  => replace(str_value(usage.expr), ":" => ": "),
        :type  => "mixin",
        :icon  => "icon-package",
        :lines => [first(usage.lines), last(usage.lines)]
    )
end
