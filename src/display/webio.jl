# TODO: this should be more robust, ideally.
using Logging, WebIO, Mux

const pages = Dict{String,Any}()
const serving = Ref{Bool}(false)
const port = Ref{Int}(9000)

function routepages(req)
    return pages[req[:params][:id]]
end

function create_silent_socket(req)
    # hide errors
    try
        WebIO.create_socket(req)
    catch err
        @debug err
    end
end

function Base.show(io::IO, ::MIME"application/juno+plotpane", n::Union{WebIO.Node, WebIO.Scope, WebIO.AbstractWidget})
    global pages, server
    id = rand(UInt128)
    pages[string(id)] = n

    if !serving[]
        setup_server()
    end
    println("http://localhost:$(port[])/$(id)")
    print(io, "<meta http-equiv=\"refresh\" content=\"0; url=http://localhost:$(port[])/$(id)\"/>")
end

function setup_server()
    port[] = rand(8000:9000)

    # hide http logging messages
    with_logger(NullLogger()) do
        @async begin
            http = Mux.App(Mux.mux(
                Mux.defaults,
                Mux.route("/:id", routepages),
                Mux.notfound()
            ))

            websock = Mux.App(Mux.mux(
                Mux.wdefaults,
                Mux.route("/webio-socket", create_silent_socket),
                Mux.wclose,
                Mux.notfound(),
            ))

            for i = 1:100
                iserr = false
                try
                    Mux.serve(http, websock, port[])
                catch err
                    iserr = true
                    port[] = rand(8000:9000)
                end
                iserr || break
            end
            serving[] = true
        end
    end
end

WebIO.setup_provider(::Val{:juno}) = setup_server()
