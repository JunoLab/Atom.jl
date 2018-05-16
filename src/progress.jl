module Progress

import Base: done
import Atom: @msg

type ProgressBar
  id::String
end

"""
    ProgressBar(;name = "", msg = "")

Create a new progress bar and register it with Juno, if possible.

Take care to unregister the progress bar by calling `done` on it, or use the
`progress(f::Function)` syntax, which will handle that automatically.
"""
function ProgressBar(;name = "", msg = "")
  p = ProgressBar(string(Base.Random.uuid1()))
  register(p)
  Progress.name(p, name)
  Progress.msg(p, msg)
  p
end

"""
    register(p::ProgressBar)

Register `p` with the Juno frontend.
"""
register(p::ProgressBar) = @msg progress("add", p)

"""
    done(p::ProgressBar)

Remove `p` from the frontend.
"""
done(p::ProgressBar) = @msg progress("delete", p)

"""
    progress(p::ProgressBar, prog::Number)

Update `p`'s progress to `prog`.
"""
progress(p::ProgressBar, prog::Real) = @msg progress("progress", p, clamp(prog, 0, 1))

"""
    progress(p::ProgressBar)

Set `p` to an indeterminate progress bar.
"""
progress(p::ProgressBar) = @msg progress("progress")

"""
    progress(f::Function; name = "", msg = "")

Evaluates `f` with `p = ProgressBar(name = name, msg = msg)` as the argument and
calls `done(p)` afterwards. This is guaranteed to clean up the progress bar,
even if `f` errors.
"""
function progress(f::Function; name = "", msg = "")
  p = ProgressBar(name = name, msg = msg)
  try
    f(p)
  finally
    done(p)
  end
end

"""
    msg(p::ProgressBar, m)

Update the message that will be displayed in the frontend when hovering over the
corrseponding progress bar.
"""
msg(p::ProgressBar, m) = @msg progress("message", p, m)

"""
    name(p::ProgressBar, m)

Update `p`s name.
"""
name(p::ProgressBar, s) = @msg progress("leftText", p, s)

"""
    right_text(p::ProgressBar, m)

Update the string that will be displayed to the right of the progress bar.

Defaults to the linearly extrpolated remaining time based upon the time
difference between registering a progress bar and the latest update.
"""
right_text(p::ProgressBar, s) = @msg progress("rightText", p, s)
end # module
