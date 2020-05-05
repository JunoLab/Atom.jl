update_project() = @msg updateProject(project_info())

# IDEA: Pkg.project will be useful for this, but it's only available as of v1.4
function project_info()
  m = match(r"^Status \`(?<path>.+)\`"m, project_status())
  m === nothing && return false
  return project_info(m[:path])
end

function project_info(path)
  return (
    name = splitpath(path)[end-1],
    path = expanduser(path)
  )
end

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

handle(project_info, "updateProject")

using Pkg: depots, API.DateTime, logdir, TOML

function allprojects()
  # First, we load in our `manifest_usage.toml` files which will tell us when our
  # "index files" (`Manifest.toml`, `Artifacts.toml`) were last used.  We will combine
  # this knowledge across depots, condensing it all down to a single entry per extant
  # index file, to manage index file growth with would otherwise continue unbounded. We
  # keep the lists of index files separated by depot so that we can write back condensed
  # versions that are only ever subsets of what we read out of them in the first place.

  # Collect last known usage dates of manifest and artifacts toml files, split by depot
  manifest_usage_by_depot = Dict{String,Dict{String,DateTime}}()
  artifact_usage_by_depot = Dict{String,Dict{String,DateTime}}()

  # Load manifest files from all depots
  for depot in Pkg.depots()
    # When a manifest/artifact.toml is installed/used, we log it within the
    # `manifest_usage.toml` files within `write_env_usage()` and `bind_artifact!()`
    function collect_usage!(usage_data::Dict, usage_filepath)
      if !isfile(usage_filepath)
        return usage_data
      end

      for (filename, infos) in TOML.parse(String(read(usage_filepath)))
        # If this file was already listed in this index, update it with the later
        # information
        for info in infos
          usage_data[filename] =
            max(get(usage_data, filename, DateTime(0)), DateTime(info["time"]))
        end
      end
      return usage_data
    end

    # Extract usage data from this depot, (taking only the latest state for each
    # tracked manifest/artifact.toml), then merge the usage values from each file
    # into the overall list across depots to create a single, coherent view across
    # all depots.
    manifest_usage_by_depot[depot] = Dict{String,DateTime}()
    artifact_usage_by_depot[depot] = Dict{String,DateTime}()
    collect_usage!(
      manifest_usage_by_depot[depot],
      joinpath(logdir(depot), "manifest_usage.toml"),
    )
    collect_usage!(
      artifact_usage_by_depot[depot],
      joinpath(logdir(depot), "artifact_usage.toml"),
    )
  end

  # Next, figure out which files are still extant
  all_index_files = vcat(
    unique(f for (_, files) in manifest_usage_by_depot for f in keys(files)),
    unique(f for (_, files) in artifact_usage_by_depot for f in keys(files)),
  )
  all_index_files = Set(filter(isfile, all_index_files))

  # Next, we will process the manifest.toml and artifacts.toml files separately,
  # extracting from them the paths of the packages and artifacts that they reference.
  all_manifest_files = filter(f -> endswith(f, "Manifest.toml"), all_index_files)
  all_artifacts_files = filter(f -> !endswith(f, "Manifest.toml"), all_index_files)

  return project_info.(collect(all_manifest_files))
end

handle(allprojects, "allProjects")
