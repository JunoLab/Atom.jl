const __bodyfunction__ = Dict{Method,Any}()

# Find keyword "body functions" (the function that contains the body
# as written by the developer, called after all missing keyword-arguments
# have been assigned values), in a manner that doesn't depend on
# gensymmed names.
# `mnokw` is the method that gets called when you invoke it without
# supplying any keywords.
function __lookup_kwbody__(mnokw::Method)
    function getsym(arg)
        isa(arg, Symbol) && return arg
        @assert isa(arg, GlobalRef)
        return arg.name
    end

    f = get(__bodyfunction__, mnokw, nothing)
    if f === nothing
        fmod = mnokw.module
        # The lowered code for `mnokw` should look like
        #   %1 = mkw(kwvalues..., #self#, args...)
        #        return %1
        # where `mkw` is the name of the "active" keyword body-function.
        ast = Base.uncompressed_ast(mnokw)
        if isa(ast, Core.CodeInfo) && length(ast.code) >= 2
            callexpr = ast.code[end-1]
            if isa(callexpr, Expr) && callexpr.head == :call
                fsym = callexpr.args[1]
                if isa(fsym, Symbol)
                    f = getfield(fmod, fsym)
                elseif isa(fsym, GlobalRef)
                    if fsym.mod === Core && fsym.name === :_apply
                        f = getfield(mnokw.module, getsym(callexpr.args[2]))
                    elseif fsym.mod === Core && fsym.name === :_apply_iterate
                        f = getfield(mnokw.module, getsym(callexpr.args[3]))
                    else
                        f = getfield(fsym.mod, fsym.name)
                    end
                else
                    f = missing
                end
            else
                f = missing
            end
        else
            f = missing
        end
        __bodyfunction__[mnokw] = f
    end
    return f
end

function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    isdefined(Atom, Symbol("#105#106")) && precompile(Tuple{getfield(Atom, Symbol("#105#106")),Hiccup.Node{:table}})
    isdefined(Atom, Symbol("#105#106")) && precompile(Tuple{getfield(Atom, Symbol("#105#106")),Juno.Model})
    isdefined(Atom, Symbol("#113#114")) && precompile(Tuple{getfield(Atom, Symbol("#113#114")),Text{String}})
    isdefined(Atom, Symbol("#144#147")) && precompile(Tuple{getfield(Atom, Symbol("#144#147")),Dict{Symbol,Any}})
    isdefined(Atom, Symbol("#146#149")) && precompile(Tuple{getfield(Atom, Symbol("#146#149")),Dict{Symbol,Any}})
    isdefined(Atom, Symbol("#171#175")) && precompile(Tuple{getfield(Atom, Symbol("#171#175"))})
    isdefined(Atom, Symbol("#181#185")) && precompile(Tuple{getfield(Atom, Symbol("#181#185"))})
    isdefined(Atom, Symbol("#193#197")) && precompile(Tuple{getfield(Atom, Symbol("#193#197"))})
    isdefined(Atom, Symbol("#200#201")) && precompile(Tuple{getfield(Atom, Symbol("#200#201")),Base.MethodList})
    isdefined(Atom, Symbol("#200#201")) && precompile(Tuple{getfield(Atom, Symbol("#200#201")),MD})
    isdefined(Atom, Symbol("#268#270")) && precompile(Tuple{getfield(Atom, Symbol("#268#270")),Dict{Symbol,Any}})
    isdefined(Atom, Symbol("#269#271")) && precompile(Tuple{getfield(Atom, Symbol("#269#271")),Dict{Symbol,Any}})
    isdefined(Atom, Symbol("#27#28")) && precompile(Tuple{getfield(Atom, Symbol("#27#28"))})
    isdefined(Atom, Symbol("#272#274")) && precompile(Tuple{getfield(Atom, Symbol("#272#274")),Atom.GotoItem})
    isdefined(Atom, Symbol("#294#296")) && precompile(Tuple{getfield(Atom, Symbol("#294#296")),Dict{Symbol,Any}})
    isdefined(Atom, Symbol("#295#297")) && precompile(Tuple{getfield(Atom, Symbol("#295#297")),Dict{Symbol,Any}})
    isdefined(Atom, Symbol("#31#32")) && precompile(Tuple{getfield(Atom, Symbol("#31#32")),String})
    isdefined(Atom, Symbol("#33#35")) && precompile(Tuple{getfield(Atom, Symbol("#33#35")),String})
    isdefined(Atom, Symbol("#49#50")) && precompile(Tuple{getfield(Atom, Symbol("#49#50")),String})
    let fbody = try __lookup_kwbody__(which(Atom.fixpath, (String,))) catch missing end
        if !ismissing(fbody)
            precompile(fbody, (String,String,typeof(Atom.fixpath),String,))
        end
    end
    precompile(Tuple{Core.kwftype(typeof(Atom.toplevelitems)),NamedTuple{(:mod, :inmod),Tuple{String,Bool}},typeof(toplevelitems),String})
    precompile(Tuple{Type{Atom.EvalError},StackOverflowError,Array{Base.StackTraces.StackFrame,1}})
    precompile(Tuple{Type{Atom.GotoItem},String,Atom.ToplevelCall})
    precompile(Tuple{Type{Atom.GotoItem},String,Atom.ToplevelMacroCall})
    precompile(Tuple{Type{Atom.GotoItem},String,Atom.ToplevelModuleUsage})
    precompile(Tuple{Type{Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{1},Axes,F,Args} where Args<:Tuple where F where Axes},typeof(todict),Tuple{Array{Any,1}}})
    precompile(Tuple{Type{Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{1},Axes,F,Args} where Args<:Tuple where F where Axes},typeof(todict),Tuple{Array{OutlineItem,1}}})
    precompile(Tuple{Type{Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{1},Axes,F,Args} where Args<:Tuple where F where Axes},typeof(|>),Tuple{Array{Any,1},Base.RefValue{typeof(todict)}}})
    precompile(Tuple{Type{Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{1},Axes,F,Args} where Args<:Tuple where F where Axes},typeof(|>),Tuple{Array{Atom.GotoItem,1},Base.RefValue{typeof(todict)}}})
    precompile(Tuple{Type{Base.RefValue},typeof(todict)})
    precompile(Tuple{Type{OutlineItem},String,String,String,Atom.ToplevelBinding})
    precompile(Tuple{Type{OutlineItem},String,String,String,Atom.ToplevelModuleUsage})
    precompile(Tuple{Type{Set},Array{OutlineItem,1}})
    precompile(Tuple{typeof(Atom._actual_localbindings),Array{Union{Atom.LocalBinding, Atom.LocalScope},1},Int64,Int64,String,Array{Any,1}})
    precompile(Tuple{typeof(Atom.appendline),String,Int64})
    precompile(Tuple{typeof(Atom.basecompletionadapter),String,String,String,Int64,Int64})
    precompile(Tuple{typeof(Atom.completion),Module,REPL.REPLCompletions.DictCompletion,String})
    precompile(Tuple{typeof(Atom.completion),Module,REPL.REPLCompletions.FieldCompletion,String})
    precompile(Tuple{typeof(Atom.completion),Module,REPL.REPLCompletions.KeywordCompletion,String})
    precompile(Tuple{typeof(Atom.completion),Module,REPL.REPLCompletions.MethodCompletion,String})
    precompile(Tuple{typeof(Atom.completion),Module,REPL.REPLCompletions.ModuleCompletion,String})
    precompile(Tuple{typeof(Atom.completion),Module,REPL.REPLCompletions.PathCompletion,String})
    precompile(Tuple{typeof(Atom.completion),Module,REPL.REPLCompletions.PropertyCompletion,String})
    precompile(Tuple{typeof(Atom.displayandrender),Module})
    precompile(Tuple{typeof(Atom.displayandrender),Symbol})
    precompile(Tuple{typeof(Atom.distance),Int64,Int64,Int64,UnitRange{Int64}})
    precompile(Tuple{typeof(Atom.docs),String})
    precompile(Tuple{typeof(Atom.eval),String,Int64,String,String})
    precompile(Tuple{typeof(Atom.evalall),String,String,String})
    precompile(Tuple{typeof(Atom.evalshow),String,Int64,String,String})
    precompile(Tuple{typeof(Atom.finddevpackages)})
    precompile(Tuple{typeof(Atom.fullREPLpath),String})
    precompile(Tuple{typeof(Atom.fullpath),String})
    precompile(Tuple{typeof(Atom.getmodule),String})
    precompile(Tuple{typeof(Atom.handlemsg),Dict{String,Any},String})
    precompile(Tuple{typeof(Atom.handlemsg),Dict{String,Any}})
    precompile(Tuple{typeof(Atom.isactive),Base.GenericIOBuffer{Array{UInt8,1}}})
    precompile(Tuple{typeof(Atom.isanon),Function})
    precompile(Tuple{typeof(Atom.localcompletion),Dict{Symbol,Any},String})
    precompile(Tuple{typeof(Atom.localdatatip),Dict{Symbol,Any},SubString{String},Int64})
    precompile(Tuple{typeof(Atom.locals),String,Int64,Int64})
    precompile(Tuple{typeof(Atom.md_hlines),MD})
    precompile(Tuple{typeof(Atom.msg),String,Int64,Vararg{Any,N} where N})
    precompile(Tuple{typeof(Atom.pkgpath),String})
    precompile(Tuple{typeof(Atom.pluralize),Array{Int64,1},String,String})
    precompile(Tuple{typeof(Atom.processdoc!),MD,String,Array{Any,1}})
    precompile(Tuple{typeof(Atom.processval!),Any,String,Array{Any,1}})
    precompile(Tuple{typeof(Atom.processval!),Function,String,Array{Any,1}})
    precompile(Tuple{typeof(Atom.renderMD),Markdown.Code})
    precompile(Tuple{typeof(Atom.renderMD),Markdown.Header{1}})
    precompile(Tuple{typeof(Atom.renderMD),Markdown.HorizontalRule})
    precompile(Tuple{typeof(Atom.renderMD),Markdown.Paragraph})
    precompile(Tuple{typeof(Atom.renderMDinline),Array{Any,1}})
    precompile(Tuple{typeof(Atom.renderMDinline),Markdown.Code})
    precompile(Tuple{typeof(Atom.renderMDinline),Markdown.Italic})
    precompile(Tuple{typeof(Atom.renderMDinline),Markdown.Link})
    precompile(Tuple{typeof(Atom.renderMDinline),String})
    precompile(Tuple{typeof(Atom.render′),Juno.Inline,Atom.Undefined})
    precompile(Tuple{typeof(Atom.render′),Juno.Inline,Function})
    precompile(Tuple{typeof(Atom.render′),Juno.Inline,Int64})
    precompile(Tuple{typeof(Atom.render′),Juno.Inline,Module})
    precompile(Tuple{typeof(Atom.render′),Juno.Inline,Nothing})
    precompile(Tuple{typeof(Atom.render′),Juno.Inline,String})
    precompile(Tuple{typeof(Atom.render′),Juno.Inline,Type{T} where T})
    precompile(Tuple{typeof(Atom.shortstr),Type{T} where T})
    precompile(Tuple{typeof(Atom.trim),Array{Float64,1},Int64})
    precompile(Tuple{typeof(Atom.withpath),Function,String})
    precompile(Tuple{typeof(Atom.wsicon),Module,Symbol,Any})
    precompile(Tuple{typeof(Atom.wsicon),Module,Symbol,Array{Any,1}})
    precompile(Tuple{typeof(Atom.wsicon),Module,Symbol,Array{String,1}})
    precompile(Tuple{typeof(Atom.wsicon),Module,Symbol,Atom.Undefined})
    precompile(Tuple{typeof(Atom.wsicon),Module,Symbol,Base.EnvDict})
    precompile(Tuple{typeof(Atom.wsicon),Module,Symbol,Function})
    precompile(Tuple{typeof(Atom.wsicon),Module,Symbol,Int64})
    precompile(Tuple{typeof(Atom.wsicon),Module,Symbol,Module})
    precompile(Tuple{typeof(Atom.wsicon),Module,Symbol,Regex})
    precompile(Tuple{typeof(Atom.wsicon),Module,Symbol,String})
    precompile(Tuple{typeof(Atom.wsicon),Module,Symbol,Type{T} where T})
    precompile(Tuple{typeof(Atom.wsicon),Module,Symbol,UInt32})
    precompile(Tuple{typeof(Atom.wsitem),Module,Symbol})
    precompile(Tuple{typeof(Atom.wstype),Module,Symbol,Any})
    precompile(Tuple{typeof(Atom.wstype),Module,Symbol,Atom.Undefined})
    precompile(Tuple{typeof(Atom.wstype),Module,Symbol,Function})
    precompile(Tuple{typeof(Atom.wstype),Module,Symbol,Module})
    precompile(Tuple{typeof(Atom.wstype),Module,Symbol,Type{T} where T})
    precompile(Tuple{typeof(Base.Broadcast.broadcasted),Function,Array{Atom.GotoItem,1},Function})
    precompile(Tuple{typeof(Base.Broadcast.broadcasted),Function,Array{OutlineItem,1}})
    precompile(Tuple{typeof(Base.Broadcast.combine_styles),Array{Any,1},Base.RefValue{typeof(todict)}})
    precompile(Tuple{typeof(Base.Broadcast.combine_styles),Array{Atom.GotoItem,1},Base.RefValue{typeof(todict)}})
    precompile(Tuple{typeof(Base.Broadcast.copyto_nonleaf!),Array{Dict{Symbol,Any},1},Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{1},Tuple{Base.OneTo{Int64}},typeof(todict),Tuple{Base.Broadcast.Extruded{Array{Any,1},Tuple{Bool},Tuple{Int64}}}},Base.OneTo{Int64},Int64,Int64})
    precompile(Tuple{typeof(Base.Broadcast.copyto_nonleaf!),Array{Dict{Symbol,Any},1},Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{1},Tuple{Base.OneTo{Int64}},typeof(todict),Tuple{Base.Broadcast.Extruded{Array{OutlineItem,1},Tuple{Bool},Tuple{Int64}}}},Base.OneTo{Int64},Int64,Int64})
    precompile(Tuple{typeof(Base.Broadcast.copyto_nonleaf!),Array{Dict{Symbol,Any},1},Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{1},Tuple{Base.OneTo{Int64}},typeof(|>),Tuple{Base.Broadcast.Extruded{Array{Any,1},Tuple{Bool},Tuple{Int64}},Base.RefValue{typeof(todict)}}},Base.OneTo{Int64},Int64,Int64})
    precompile(Tuple{typeof(Base.Broadcast.copyto_nonleaf!),Array{Dict{Symbol,Any},1},Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{1},Tuple{Base.OneTo{Int64}},typeof(|>),Tuple{Base.Broadcast.Extruded{Array{Atom.GotoItem,1},Tuple{Bool},Tuple{Int64}},Base.RefValue{typeof(todict)}}},Base.OneTo{Int64},Int64,Int64})
    precompile(Tuple{typeof(Base.Broadcast.copyto_nonleaf!),Array{Nothing,1},Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{1},Tuple{Base.OneTo{Int64}},typeof(Atom.outlineitem),Tuple{Base.Broadcast.Extruded{Array{Atom.ToplevelItem,1},Tuple{Bool},Tuple{Int64}}}},Base.OneTo{Int64},Int64,Int64})
    precompile(Tuple{typeof(Base.Broadcast.copyto_nonleaf!),Array{OutlineItem,1},Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{1},Tuple{Base.OneTo{Int64}},typeof(Atom.outlineitem),Tuple{Base.Broadcast.Extruded{Array{Atom.ToplevelItem,1},Tuple{Bool},Tuple{Int64}}}},Base.OneTo{Int64},Int64,Int64})
    precompile(Tuple{typeof(Base.Broadcast.materialize),Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{1},Nothing,typeof(todict),Tuple{Array{Any,1}}}})
    precompile(Tuple{typeof(Base.Broadcast.materialize),Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{1},Nothing,typeof(todict),Tuple{Array{OutlineItem,1}}}})
    precompile(Tuple{typeof(Base.Broadcast.materialize),Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{1},Nothing,typeof(|>),Tuple{Array{Any,1},Base.RefValue{typeof(todict)}}}})
    precompile(Tuple{typeof(Base.Broadcast.materialize),Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{1},Nothing,typeof(|>),Tuple{Array{Atom.GotoItem,1},Base.RefValue{typeof(todict)}}}})
    precompile(Tuple{typeof(Base._promote_typejoin),Type{Nothing},Type{OutlineItem}})
    precompile(Tuple{typeof(Base.collect_to!),Array{Any,1},Base.Generator{Array{Any,1},typeof(Atom.renderMDinline)},Int64,Int64})
    precompile(Tuple{typeof(Base.collect_to!),Array{Hiccup.Node,1},Base.Generator{Array{Any,1},typeof(Atom.renderMD)},Int64,Int64})
    precompile(Tuple{typeof(Base.collect_to_with_first!),Array{Hiccup.Node{:code},1},Hiccup.Node{:code},Base.Generator{Array{Any,1},typeof(Atom.renderMDinline)},Int64})
    precompile(Tuple{typeof(Base.collect_to_with_first!),Array{Hiccup.Node{:div},1},Hiccup.Node{:div},Base.Generator{Array{Any,1},typeof(Atom.renderMD)},Int64})
    precompile(Tuple{typeof(Base.collect_to_with_first!),Array{Hiccup.Node{:pre},1},Hiccup.Node{:pre},Base.Generator{Array{Any,1},typeof(Atom.renderMD)},Int64})
    precompile(Tuple{typeof(Base.collect_to_with_first!),Array{String,1},String,Base.Generator{Array{Any,1},typeof(Atom.renderMDinline)},Int64})
    precompile(Tuple{typeof(Juno.view),Dict{Any,Any}})
    precompile(Tuple{typeof(Juno.view),Dict{Symbol,Any}})
    precompile(Tuple{typeof(Juno.view),Hiccup.Node{:a}})
    precompile(Tuple{typeof(Juno.view),Hiccup.Node{:em}})
    precompile(Tuple{typeof(Juno.view),Hiccup.Node{:h1}})
    precompile(Tuple{typeof(Juno.view),Hiccup.Node{:hr}})
    precompile(Tuple{typeof(Juno.view),Hiccup.Node{:pre}})
    precompile(Tuple{typeof(Juno.view),Hiccup.Node{:p}})
    precompile(Tuple{typeof(Juno.view),Hiccup.Node{:td}})
    precompile(Tuple{typeof(Juno.view),Hiccup.Node{:tr}})
    precompile(Tuple{typeof(Juno.view),Method})
    precompile(Tuple{typeof(Juno.view),String})
    precompile(Tuple{typeof(Juno.view),SubString{String}})
    precompile(Tuple{typeof(Media.render),Juno.Inline,Atom.EvalError{StackOverflowError}})
    precompile(Tuple{typeof(Media.render),Juno.Inline,Hiccup.Node{:div}})
    precompile(Tuple{typeof(Media.render),Juno.Inline,Hiccup.Node{:span}})
    precompile(Tuple{typeof(Media.render),Juno.Inline,Juno.Model})
    precompile(Tuple{typeof(Media.render),Juno.Inline,Module})
    precompile(Tuple{typeof(Media.render),Juno.Inline,Symbol})
    precompile(Tuple{typeof(Media.render),Juno.Inline,Text{String}})
    precompile(Tuple{typeof(Media.render),Juno.Inline,Type{T} where T})
    precompile(Tuple{typeof(clearsymbols)})
    precompile(Tuple{typeof(convert),Type{Array{OutlineItem,1}},Array{OutlineItem,1}})
    precompile(Tuple{typeof(convert),Type{Array{OutlineItem,1}},Array{Union{Nothing, OutlineItem},1}})
    precompile(Tuple{typeof(delete!),Dict{String,Dict{String,Array{Atom.GotoItem,1}}},String})
    precompile(Tuple{typeof(find_project_file),String})
    precompile(Tuple{typeof(getdocs),Module,String})
    precompile(Tuple{typeof(getfield′),Any,String,Atom.Undefined})
    precompile(Tuple{typeof(getfield′),Any,String})
    precompile(Tuple{typeof(getfield′),Any,Symbol,Atom.Undefined})
    precompile(Tuple{typeof(getfield′),Any,Symbol})
    precompile(Tuple{typeof(getfield′),Module,String})
    precompile(Tuple{typeof(getfield′),Module,Symbol,Function})
    precompile(Tuple{typeof(getfield′),Module,Symbol})
    precompile(Tuple{typeof(getindex),Dict{String,Array{Atom.GotoItem,1}},String})
    precompile(Tuple{typeof(globaldatatip),String,String})
    precompile(Tuple{typeof(globalgotoitems),String,Module,Nothing,String})
    precompile(Tuple{typeof(globalgotoitems),String,Module,String,String})
    precompile(Tuple{typeof(in),OutlineItem,Set{OutlineItem}})
    precompile(Tuple{typeof(ismacro),Function})
    precompile(Tuple{typeof(ismacro),String})
    precompile(Tuple{typeof(isundefined),Atom.Undefined})
    precompile(Tuple{typeof(isundefined),Function})
    precompile(Tuple{typeof(keys),Dict{String,Array{Atom.GotoItem,1}}})
    precompile(Tuple{typeof(length),Base.KeySet{String,Dict{String,Array{Atom.GotoItem,1}}}})
    precompile(Tuple{typeof(length),Base.KeySet{String,Dict{String,Dict{String,Array{Atom.GotoItem,1}}}}})
    precompile(Tuple{typeof(length),Dict{String,Array{Atom.GotoItem,1}}})
    precompile(Tuple{typeof(map),Function,Array{OutlineItem,1}})
    precompile(Tuple{typeof(moduledefinition),Module})
    precompile(Tuple{typeof(modulefiles),Module})
    precompile(Tuple{typeof(modulefiles),String,String})
    precompile(Tuple{typeof(regeneratesymbols)})
    precompile(Tuple{typeof(searchcodeblocks),MD})
    precompile(Tuple{typeof(setindex!),Array{OutlineItem,1},OutlineItem,Int64})
    precompile(Tuple{typeof(setindex!),Array{Union{Atom.LocalBinding, Atom.LocalScope},1},Atom.LocalBinding,Int64})
    precompile(Tuple{typeof(setindex!),Array{Union{Atom.LocalBinding, Atom.LocalScope},1},Atom.LocalScope,Int64})
    precompile(Tuple{typeof(similar),Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{1},Tuple{Base.OneTo{Int64}},typeof(Atom.outlineitem),Tuple{Base.Broadcast.Extruded{Array{Atom.ToplevelItem,1},Tuple{Bool},Tuple{Int64}}}},Type{Nothing}})
    precompile(Tuple{typeof(similar),Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{1},Tuple{Base.OneTo{Int64}},typeof(Atom.outlineitem),Tuple{Base.Broadcast.Extruded{Array{Atom.ToplevelItem,1},Tuple{Bool},Tuple{Int64}}}},Type{OutlineItem}})
    precompile(Tuple{typeof(similar),Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{1},Tuple{Base.OneTo{Int64}},typeof(todict),Tuple{Base.Broadcast.Extruded{Array{Any,1},Tuple{Bool},Tuple{Int64}}}},Type{Dict{Symbol,Any}}})
    precompile(Tuple{typeof(similar),Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{1},Tuple{Base.OneTo{Int64}},typeof(todict),Tuple{Base.Broadcast.Extruded{Array{OutlineItem,1},Tuple{Bool},Tuple{Int64}}}},Type{Dict{Symbol,Any}}})
    precompile(Tuple{typeof(similar),Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{1},Tuple{Base.OneTo{Int64}},typeof(|>),Tuple{Base.Broadcast.Extruded{Array{Any,1},Tuple{Bool},Tuple{Int64}},Base.RefValue{typeof(todict)}}},Type{Dict{Symbol,Any}}})
    precompile(Tuple{typeof(similar),Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{1},Tuple{Base.OneTo{Int64}},typeof(|>),Tuple{Base.Broadcast.Extruded{Array{Atom.GotoItem,1},Tuple{Bool},Tuple{Int64}},Base.RefValue{typeof(todict)}}},Type{Dict{Symbol,Any}}})
    precompile(Tuple{typeof(sprint),Function,Base.Generator{CSTParser.EXPR,typeof(Atom.str_value)}})
    precompile(Tuple{typeof(strlimit),String,Int64})
    precompile(Tuple{typeof(toplevelgotoitems),String,Module,String,Nothing})
    precompile(Tuple{typeof(toplevelitems),String})
    precompile(Tuple{typeof(updatesymbols),String,String,String})
    precompile(Tuple{typeof(use_compiled_modules)})
    precompile(Tuple{typeof(vcat),OutlineItem,OutlineItem,OutlineItem,Vararg{OutlineItem,N} where N})
    precompile(Tuple{typeof(workspace),String})
    precompile(Tuple{typeof(|>),Array{Atom.GotoItem,1},typeof(isempty)})
    precompile(Tuple{typeof(|>),Array{Atom.ToplevelItem,1},typeof(length)})
end
