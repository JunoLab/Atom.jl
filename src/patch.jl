eval(Base, quote
import Atom
import MacroTools
end)

eval(Base, quote

MacroTools.@hook function info(msg...)
  if Atom.isconnected()
    Atom.@msg info(string(msg...))
  else
    super(msg...)
  end
end

end)
