project_status() = read(steal_stdout(Pkg.status), String)

function steal_stdout(f)
  old = stdout
  rd, wr = redirect_stdout()
  try
    f()
  finally
    redirect_stdout(old)
    close(wr)
  end
  return rd
end

@static if VERSION < v"1.1"

update_project() = @msg updateProject(false)
handle(()->false, "allProjects")

else

update_project() = @msg updateProject(project_info())

# IDEA: Pkg.project will be useful for this, but it's only available as of v1.4
function project_info()
  m = match(r"Status \`(?<path>.+)\`$"m, project_status())
  m === nothing && return false
  return project_info(m[:path])
end

function project_info(path)
  path = string(expanduser(path))
  return (
    name = Pkg.REPLMode.projname(path),
    path = path,
  )
end

# adapted from https://github.com/JuliaLang/Pkg.jl/blob/eb3726d8f9c68bb91707a5c0e9809c95f1c1eee7/src/API.jl#L331-L726
# but here we only look at "user-depot" and collect usages of each Manifest.toml
using Pkg.TOML, Dates

function allprojects()
  manifest_usage = Dict{String,DateTime}()
  usagefile_path = joinpath(Base.DEPOT_PATH[1], "logs", "manifest_usage.toml")
  isfile(usagefile_path) || return (projects = [], active = "")
  for (filename, infos) in TOML.parse(read(usagefile_path, String))
    for info in infos
      manifest_usage[filename] = max(get(manifest_usage, filename, DateTime(0)), DateTime(info["time"]))
    end
  end

  # IDEA: maybe filtering dated manifests ?
  all_project_files = map(collect(keys(manifest_usage))) do f
    replace(f, "Manifest.toml" => "Project.toml")
  end
  filter!(isfile, all_project_files)
  projects = project_info.(all_project_files)
  active = project_info().name
  return (projects = projects, active = active)
end

handle(allprojects, "allProjects")

end  # if VERSION < v"1.1"
