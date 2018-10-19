module TableViewer
using Tables, WebIO, JSExpr
using ..Atom
using Dates

function showtable(x)
    w = _showtable(x)
    str = string("data:text/html,", sprint(io -> show(io, "application/juno+plotpane", w)))
    Atom.msg("jlpane", "asd", Dict(:url=>str, :title=>"Table Viewer", :devtools => true))
    nothing
end

function _showtable(x)
    w = Scope(imports=["https://unpkg.com/ag-grid-community/dist/ag-grid-community.min.noStyle.js",
                       "https://unpkg.com/ag-grid-community/dist/styles/ag-grid.css",
                       "https://unpkg.com/ag-grid-community/dist/styles/ag-theme-balham-dark.css",])

    schema = Tables.schema(x)
    names = schema.names
    types = schema.types

    coldefs = [(
                    headerName = n,
                    field = n,
                    type = types[i] <: Union{Missing, T where T <: Number} ? "numericColumn" : nothing,
                    filter = types[i] <: Union{Missing, T where T <: Dates.Date} ? "agDateColumnFilter" :
                             types[i] <: Union{Missing, T where T <: Number} ? "agNumberColumnFilter" : nothing
               ) for (i, n) in enumerate(names)]

    options = Dict(
        # :rowData => rendertable(x, names),
        :rowData => table2json(x),
        :columnDefs => coldefs,
        :enableSorting => true,
        :enableFilter => true,
        :enableColResize => true,
        :multiSortKey => "ctrl"
    )

    handler = @js function (agGrid)
        gridOptions = $options
        gridOptions.rowData = JSON.parse(gridOptions.rowData)
        this.table = @new agGrid.Grid(this.dom.querySelector("#grid"), gridOptions)
        gridOptions.columnApi.autoSizeColumns($names)
    end
    onimport(w, handler)
    w.dom = dom"div#grid.ag-theme-balham-dark"(style=Dict(:position => "absolute",
                                                     :top => "0",
                                                     :left => "0",
                                                     :width => "100%",
                                                     :height => "100%",
                                                     :minHeight => "200px"))
    w
end

using JSON
# directly write JSON instead of allocating temporary dicts etc
function table2json(table)
    names = Tables.schema(table).names

    nrows = length(Tables.rows(table))
    ncols = length(names)

    io = IOBuffer()
    print(io, '[')
    for row in Tables.rows(table)
        print(io, '{')
        i = 1
        for col in Tables.eachcolumn(row)
            JSON.print(io, names[i])
            i += 1
            print(io, ':')
            if col isa Number
                JSON.print(io, col)
            else
                JSON.print(io, sprint(print, col))
            end
            print(io, ',')
        end
        skip(io, -1)
        print(io, '}')
        print(io, ',')
    end
    skip(io, -1)
    print(io, ']')

    String(take!(io))
end


function rendertable(x, names)
    out = []
    for row in Tables.rows(x)
        inner = Dict{Symbol, Any}()
        for (i, col) in enumerate(Tables.eachcolumn(row))
            if col isa Number
                inner[names[i]] = col
            else
                inner[names[i]] = sprint(print, col)
            end
        end
        push!(out, inner)
    end
    out
end
end
