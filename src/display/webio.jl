# TODO: this should be more robust, ideally.
using Logging
import WebIO, HTTP, WebSockets

const pages = Dict{String,Any}()
const server = Ref{Any}()
const port = Ref{Int}(9000)

function isrunning(server)
    isassigned(server) && !istaskdone(server[].serve_task)
end

# Be ready for the deprecation of tohtml :P
# once the no unsafe-script lands
if isdefined(WebIO, :tohtml)
    const tohtml = WebIO.tohtml
else
    tohtml(io, app) = show(io, MIME"text/html"(), app)
end

function routepages(req)
    target = req.target[2:end]

    haskey(pages, target) || return missing

    io = IOBuffer()
    webio_script = WebIO.wio_asseturl("/webio/dist/bundle.js")
    ws_script = WebIO.wio_asseturl("/providers/websocket_connection.js")
    print(io, """
        <!doctype html>
        <html>
        <head>
        <meta charset="UTF-8">
        <script>var websocket_url = 'ws://localhost:$(port[])/webio_websocket'</script>
        <script src=$(repr(webio_script))></script>
        <script src=$(repr(ws_script))></script>
        </head>
        <body>
    """)
    tohtml(io, pages[target])
    print(io, """
        </body>
        </html>
    """)

    return HTTP.Response(
        200,
        ["Content-Type" => "text/html"],
        body = String(take!(io))
    )
end

function Base.show(io::IO, ::MIME"application/juno+plotpane", n::Union{WebIO.Node, WebIO.Scope, WebIO.AbstractWidget})
    global pages, server
    id = rand(UInt128)
    pages[string(id)] = WebIO.render(n)

    if !isrunning(server)
        server[] = setup_server()
    end

    print(io, "<meta http-equiv=\"refresh\" content=\"0; url=http://localhost:$(port[])/$(id)\"/>")
end

function setup_server()
    port[] = rand(8000:9000)

    server = nothing
    # STFU
    with_logger(Logging.NullLogger()) do
        server = WebIO.WebIOServer(
            routepages,
            http_port = port[],
            singleton = false
        )
    end

    return server
end
