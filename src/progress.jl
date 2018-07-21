module Progress
using Logging

using Atom: msg

const progs = Set()

"""
    JunoProgressLogger(previous_logger<:AbstractLogger)

Logger that only handles messages with `progress` argument set and passes all
others throught to the previously defined logger.

If the `progress` argument is set then a corresponding progress bar will be shown
in the Juno frontend with it's name set to the logging message.

Possible keyword arguments to logging messages consumed by this logger are:
  - `progress`:
    - `0 <= progress < 1`: create or update progress bar
    - `progress == nothing || progress = NaN`: set progress bar to indeterminate progress
    - `progress > 1 || progress == "done"`: destroy progress bar
  - `right_text`: Shown instead of a approximation of remaining time.
  - `_id`: Should be set to a symbol for updates to a progress bar if they are
    not occuring on the same line.
"""
struct JunoProgressLogger <: AbstractLogger
  previous_logger
end

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
  else
    if Logging.shouldlog(j.previous_logger, level, _module, group, id)
      Logging.handle_message(j.previous_logger, level, message, _module,
                             group, id, file, line; kwargs...)
    end
  end
end

Logging.shouldlog(::JunoProgressLogger, level, _module, group, id) = true

Logging.catch_exceptions(::JunoProgressLogger) = true

Logging.min_enabled_level(::JunoProgressLogger) = Logging.BelowMinLevel
end
