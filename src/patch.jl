import Atom, MacroTools

MacroTools.@hook function info(msg...)
  if Atom.isconnected()
    Atom.msg("info", Dict(:msg=>string(msg...)))
  else
    super(msg...)
  end
end
