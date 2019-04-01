uri_regex = if Sys.iswindows()
  r"((?:(?:[a-zA-Z]:|\.\.?|\~)|(?:[^\0<>\?\|\/\s!$`&*()\[\]+'\":;])+)?(?:(?:\\|\/)(?:[^\0<>\?\|\/\s!$`&*()\[\]+'\":;])+)+)(?:\:(\d+))?"
else
  r"((?:(?:\.\.?|\~)|(?:[^\0\s!$`&*()\[\]+'\":;\\])+)?(?:\/(?:[^\0\s!$`&*()\[\]+'\":;\\])+)+)(?:\:(\d+))?"
end

repl_at_regex = r"@ (?:[^\s]+)\s(.*?)\:(\d+)"

function fullREPLpath(uri)
  urimatch = match(repl_at_regex, uri)
  if urimatch ≠ nothing
    return normpath(expanduser(String(urimatch[1]))), parse(Int, urimatch[2])
  else
    urimatch = match(uri_regex, uri)
    if urimatch ≠ nothing
      line = urimatch[2] ≠ nothing ? parse(Int, urimatch[2]) : 0
      return Atom.fullpath(normpath(expanduser(String(urimatch[1])))), line
    end
  end
  return "", 0
end
