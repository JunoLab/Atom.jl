select(items) = get(rpc("select", @d(:items=>items)), "item", nothing)
