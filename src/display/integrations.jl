using Gadfly

@render Inline p::Gadfly.Plot begin
  Tree(Text("Plot"),
       [div(d(:style=>"background: white; width: 150%"),
            HTML(stringmime("text/html", p)))])
end
