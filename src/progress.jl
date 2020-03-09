module Progress
using Logging

using Atom: msg

const progs = Set()

"""
    JunoProgressLogger()

Logger that only handles messages with `progress` argument set and passes all
others through to the `global_logger`.

If the `progress` argument is set, then a progress bar will be shown in the Juno frontend.

Possible keyword arguments to logging messages consumed by this logger are:
  - `progress`:
    - `0 <= progress < 1`: create or update progress bar
    - `progress == nothing || progress = NaN`: set progress bar to indeterminate progress
    - `progress > 1 || progress == "done"`: destroy progress bar
  - `right_text`: Shown instead of a approximation of remaining time.
  - `message`: Shown in a tooltip.
  - `_id`: The progress bars' ID. Should be set (to a symbol or string) in most cases.
"""
struct JunoProgressLogger <: AbstractLogger end

function Logging.handle_message(j::JunoProgressLogger, level, message, _module,
                                group, id, file, line; kwargs...)
  if haskey(kwargs, :progress)
    if !(id in progs)
      push!(progs, id)
      msg("progress", "add", id)
    end
    msg("progress", "leftText", id, message)

    prog = kwargs[:progress]
    if prog isa Real
      if 0 <= prog < 1
        msg("progress", "progress", id, prog)
      elseif prog >= 1
        msg("progress", "delete", id)
        delete!(progs, id)
      end
    elseif prog isa Nothing
      msg("progress", "progress", id, NaN)
    elseif prog isa AbstractString && prog == "done"
      msg("progress", "delete", id)
      delete!(progs, id)
    else
      msg("progress", "progress", id, NaN)
    end

    if haskey(kwargs, :right_text)
      msg("progress", "rightText", id, kwargs[:right_text])
    end

    if haskey(kwargs, :message)
      msg("progress", "message", id, kwargs[:message])
    end
  else
    previous_logger = Logging.global_logger()
    if (Base.invokelatest(Logging.min_enabled_level, previous_logger) <= Logging.LogLevel(level) ||
        Base.CoreLogging.env_override_minlevel(group, _module)) &&
        Base.invokelatest(Logging.shouldlog, previous_logger, level, _module, group, id)
      Logging.handle_message(previous_logger, level, message, _module,
                             group, id, file, line; kwargs...)
    end
  end
  return nothing
end

Logging.shouldlog(::JunoProgressLogger, level, _module, group, id) = true

Logging.catch_exceptions(::JunoProgressLogger) = true

function Logging.min_enabled_level(j::JunoProgressLogger)
  min(Base.invokelatest(Logging.min_enabled_level, Logging.global_logger()), Logging.LogLevel(-1))
end


end # module
