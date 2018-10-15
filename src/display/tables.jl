module TableViewer
using Tables, WebIO, JSExpr
using ..Atom

function showtable(x)
    w = _showtable(x)
    str = string("data:text/html,", sprint(io -> show(io, "application/juno+plotpane", w)))
    Atom.msg("jlpane", "asd", Dict(:url=>str, :title=>"Table Viewer"))
    nothing
end

function _showtable(x)
    w = Scope(imports=["https://cdn.jsdelivr.net/npm/handsontable@6.0.1/dist/handsontable.full.min.js",
                       "https://cdn.jsdelivr.net/npm/handsontable@6.0.1/dist/handsontable.full.min.css"])

    schema = Tables.schema(x)
    names = schema.names

    options = Dict(
        :data => rendertable(x),
        :colHeaders => names,
        :manualColumnResize => true,
        :manualRowResize => true,
        :filters => true
    )

    handler = @js function (Handsontable)
        @var sizefix = document.createElement("style");
        sizefix.textContent = """
            .htCore td {
                white-space:nowrap
            }
        """
        this.dom.appendChild(sizefix)
        this.hot = @new Handsontable(this.dom.getElementsByClassName("bar")[0], $options);
    end
    onimport(w, handler)
    w.dom = dom"div.foo"(dom"div.bar"())
    w
end

function rendertable(x)
    out = []
    for row in Tables.rows(x)
        inner = []
        for col in Tables.eachcolumn(row)
            push!(inner, sprint(show, col))
        end
        push!(out, inner)
    end
    out
end
end
