module TableViewer
using Tables, WebIO, JSExpr
using ..Atom

function showtable(x)
    w = _showtable(x)
    str = string("data:text/html,", sprint(io -> show(io, "application/juno+plotpane", w)))
    Atom.msg("jlpane", "asd", Dict(:url=>str, :title=>"Table Viewer", :devtools => true))
    nothing
end

function _showtable(x)
    w = Scope(imports=["https://unpkg.com/ag-grid-community/dist/ag-grid-community.min.noStyle.js",
                       "https://unpkg.com/ag-grid-community/dist/styles/ag-grid.css",
                       "https://unpkg.com/ag-grid-community/dist/styles/ag-theme-balham.css",])

    schema = Tables.schema(x)
    names = schema.names

    coldefs = [(headerName = n, field = n) for n in names]

    options = Dict(
        :rowData => rendertable(x, names),
        :columnDefs => coldefs,
        :enableSorting => true,
        :enableFilter => true
    )

    handler = @js function (agGrid)
        this.table = @new agGrid.Grid(this.dom.querySelector("#grid"), $options)
    end
    onimport(w, handler)
    w.dom = dom"div#grid.ag-theme-balham"(style=Dict(:position => "absolute",
                                                     :top => "0",
                                                     :left => "0",
                                                     :width => "100vw",
                                                     :height => "100vh"))
    w
end

function rendertable(x, names)
    out = []
    for row in Tables.rows(x)
        inner = Dict{Symbol, String}()
        for (i, col) in enumerate(Tables.eachcolumn(row))
            inner[names[i]] = sprint(show, col)
        end
        push!(out, inner)
    end
    out
end
end
