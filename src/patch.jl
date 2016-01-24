eval(Base, quote
import Atom
end)

eval(Base, quote

Requires.@hook function info(msg...)
  if Atom.isconnected()
    Atom.@msg info(string(msg...))
  else
    super(msg...)
  end
end

end)
