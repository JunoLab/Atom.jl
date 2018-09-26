# TODO: this should be more robust, ideally.
using Logging
import WebIO, HTTP, WebSockets

const pages = Dict{String,Any}()
const serving = Ref{Bool}(false)
const port = Ref{Int}(9000)

function routepages(req)
    target = req.target[2:end]

    haskey(pages, target) || return missing

    io = IOBuffer()
    webio_script = WebIO.wio_asseturl("/webio/dist/bundle.js")
    ws_script = WebIO.wio_asseturl("/providers/websocket_connection.js")

    println(io, "<head>")
    println(io, "<script> var websocket_url = 'localhost:$(port[])/webio_websocket' </script>")
    println(io, "<script src=$(repr(webio_script))></script>")
    println(io, "<script src=$(repr(ws_script))   ></script>")
    println(io, "</head><body>")
    WebIO.tohtml(io, pages[target])
    println(io, "</body>")
    str = String(take!(io))

    return HTTP.Response(
        200,
        ["Content-Type" => "text/html"],
        body = str
    )
end

function Base.show(io::IO, ::MIME"application/juno+plotpane", n::Union{WebIO.Node, WebIO.Scope, WebIO.AbstractWidget})
    global pages, server
    id = rand(UInt128)
    pages[string(id)] = WebIO.render(n)

    if !serving[]
        setup_server()
    end

    print(io, "<meta http-equiv=\"refresh\" content=\"0; url=http://localhost:$(port[])/$(id)\"/>")
end

function setup_server()
    port[] = 8888 #rand(8000:9000)
    server = nothing

    # STFU
    with_logger(Logging.NullLogger()) do
        server = WebIO.WebIOServer(
            routepages,
            http_port = port[],
            singleton = false
        )
    end

    serving[] = true

    return server
end
