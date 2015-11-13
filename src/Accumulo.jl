module Accumulo

using Thrift

import Base: close, isready, show, eof, start, next, done
import Thrift: flush

export AccumuloSession, AccumuloAuth, AccumuloAuthSASLPlain
export close

# export useful enums
#export PartialKey, TablePermission, SystemPermission, ScanType, ScanState, CompactionType, CompactionReason, TimeType
export IteratorScope, Durability, ConditionalStatus

# export useful types
export Key, KeyValue, IteratorSetting

# export table administration commands
# TODO: namespaces
export table_clone, table_create, table_delete, table_rename, table_du, table_config, table_config!, table_versions!, table_export, table_import, table_offline, table_online, table_exists, tables

# export table control commands
# TODO: locality groups, compaction
export flush, constraints, add_constraints, remove_constraints, table_splits, table_split, table_merge

# export table iterators
export iter, iters, add_iter, remove_iter, check_iter

# export writer functions
export batch, conditional_batch, batch_writer, conditional_batch_writer, where, update, delete, close, flush

# export scanner functions
export scanner, scanner_key, records, close, eof, start, next, done

## enable logging only during debugging
#using Logging
#const logger = Logging.configure(level=DEBUG)
##const logger = Logging.configure(filename="/tmp/accumulo$(getpid()).log", level=DEBUG)
#macro logmsg(s)
#    quote
#        debug($(esc(s)))
#    end
#end
macro logmsg(s)
end

include("proxy/proxy.jl")
using .proxy
import .proxy: update
include("types.jl")
include("sess.jl")
include("table_admin.jl")
include("table_control.jl")
include("iter.jl")
include("writers.jl")
include("scanners.jl")

end # module
