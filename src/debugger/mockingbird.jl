# mock implementation for Julia versions where the Debugger doesn't work
module Debugger
isdebugging() = false
end
