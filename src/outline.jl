handle("updateeditor") do data
    @destruct [
        text || "",
        mod || "Main",
        path || nothing,
        updateSymbols || true
    ] = data

    return try
        todict.(updateeditor(text, mod, path, updateSymbols))
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

struct OutlineItem
    name::String
    type::String
    icon::String
    start::Int
    stop::Int
end
OutlineItem(name, type, icon, item::ToplevelItem) =
    OutlineItem(name, type, icon, first(item.lines), last(item.lines))

# for messaging over julia ⟷ Atom
todict(item::OutlineItem) = Dict(
    :name  => item.name,
    :type  => item.type,
    :icon  => item.icon,
    :start => item.start,
    :stop  => item.stop
)

outline(items)::Vector{OutlineItem} = filter!(item -> item !== nothing, outlineitem.(items))

outlineitem(item::ToplevelItem) = nothing # fallback case
outlineitem(binding::ToplevelBinding) = begin
    expr = binding.expr
    bind = binding.bind
    name = CSTParser.has_sig(expr) ? str_value(CSTParser.get_sig(expr)) : bind.name
    OutlineItem(name, static_type(bind), static_icon(bind), binding)
end
outlineitem(call::ToplevelCall) = begin
    # show includes
    if isinclude(call.expr)
        return OutlineItem(call.str, "module", "icon-file-code", call)
    end
    nothing
end
outlineitem(macrocall::ToplevelMacroCall) = begin
    # don't show doc strings
    isdoc(macrocall.expr) && return nothing
    # show first line verbatim of macro calls
    verbatim = strlimit(first(split(macrocall.str, '\n')), 100)
    OutlineItem(verbatim, "snippet", "icon-mention", macrocall)
end
outlineitem(usage::ToplevelModuleUsage) = begin
    useline = replace(str_value(usage.expr), ":" => ": ")
    OutlineItem(useline, "mixin", "icon-package", usage)
end
