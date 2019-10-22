const uri_regex = @static if Sys.iswindows()
  r"((?:(?:[a-zA-Z]:|\.\.?|\~)|(?:[^\0<>\?\|\/\s!$`&*()\[\]+'\":;])+)?(?:(?:\\|\/)(?:[^\0<>\?\|\/\s!$`&*()\[\]+'\":;])+)+)(?:\:(\d+))?"
else
  r"((?:(?:\.\.?|\~)|(?:[^\0\s!$`&*()\[\]+'\":;\\])+)?(?:\/(?:[^\0\s!$`&*()\[\]+'\":;\\])+)+)(?:\:(\d+))?"
end

const buildbot_regex = @static if Sys.iswindows()
  r"C:\\cygwin\home\\Admininstrator\\buildbot\\.*?(\\julia\\stdlib\\.*?\.jl)"
else
  r"\/buildworker\/worker\/.*?(\/julia\/stdlib\/.*?\.jl)"
end

const repl_at_regex = r"@ (?:[^\s]+)\s(.*?)\:(\d+)"

function fullREPLpath(uri)
  urimatch = match(repl_at_regex, uri)
  if urimatch ≠ nothing
    return normpath(expanduser(String(urimatch[1]))), parse(Int, urimatch[2])
  else
    urimatch = match(uri_regex, uri)
    if urimatch ≠ nothing
      line = urimatch[2] ≠ nothing ? parse(Int, urimatch[2]) : 0
      path = fix_buildbot_path(String(urimatch[1]))
      return Atom.expandpath(path)[2], line
    end
  end
  return "", 0
end

function fix_buildbot_path(path)
  urimatch = match(buildbot_regex, path)
  if urimatch ≠ nothing
    path = urimatch[1]
  end

  return path
end
