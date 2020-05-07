handle("updateeditor") do data
    @destruct [
        text || "",
        mod || "Main",
        path || nothing,
        updateSymbols || true
    ] = data

    return try
        updateeditor(text, mod, path, updateSymbols)
    catch err
        OutlineItem[]
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

struct OutlineItem
    name::String
    type::String
    icon::String
    start::Int
    stop::Int
end
OutlineItem(name, type, icon, item::ToplevelItem) =
    OutlineItem(name, type, icon, first(item.lines), last(item.lines))

outline(items) = filter!(item -> item !== nothing, outlineitem.(items))::Vector{OutlineItem}

outlineitem(item::ToplevelItem) = nothing # fallback case
outlineitem(binding::ToplevelBinding) = begin
    expr = binding.expr
    bind = binding.bind
    name = CSTParser.has_sig(expr) ? str_value(CSTParser.get_sig(expr)) : bind.name
    OutlineItem(name, static_type(bind), static_icon(bind), binding)
end
outlineitem(call::ToplevelCall) = begin
    # show includes
    return if isinclude(call.expr)
        OutlineItem(call.verbatim, "module", "icon-file-code", call)
    elseif isprecompile(call.expr)
        OutlineItem(call.verbatim, "module", "icon-file-binary", call)
    else
        nothing
    end
end
outlineitem(macrocall::ToplevelMacroCall) = begin
    # don't show doc strings
    isdoc(macrocall.expr) && return nothing
    # show first line verbatim of macro calls
    firstline = strlimit(first(split(macrocall.verbatim, '\n')), 100)
    OutlineItem(firstline, "snippet", "icon-mention", macrocall)
end
outlineitem(usage::ToplevelModuleUsage) = begin
    useline = replace(str_value(usage.expr), ":" => ": ")
    OutlineItem(useline, "mixin", "icon-package", usage)
end
