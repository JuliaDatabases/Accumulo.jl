module Accumulo

using Thrift

import Base: close, isready, show, eof, start, next, done
import Thrift: flush

export AccumuloSession, AccumuloAuth, AccumuloAuthSASLPlain
export close

# export useful enums
#export PartialKey, TablePermission, SystemPermission, ScanType, ScanState, ConditionalStatus, Durability, CompactionType, CompactionReason, IteratorScope, TimeType

# export table administration commands
# TODO: namespaces
export clone_table, create_table, delete_table, rename_table, du, config, export_table, import_table, offline, online, tables

# export table  control commands
# TODO: locality groups
export flush, constraints, add_constraints, remove_constraints, splits, split, merge

# enable logging only during debugging
using Logging
const logger = Logging.configure(level=DEBUG)
#const logger = Logging.configure(filename="/tmp/accumulo$(getpid()).log", level=DEBUG)
macro logmsg(s)
    quote
        debug($(esc(s)))
    end
end
#macro logmsg(s)
#end

include("proxy/proxy.jl")
using .proxy
include("types.jl")
include("sess.jl")
include("table_admin.jl")
include("table_control.jl")

end # module
