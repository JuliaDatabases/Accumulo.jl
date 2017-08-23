# add, merge or list split points to an existing table
function table_split(session::AccumuloSession, tablename::String, splits...)
    splitset = Set([bytes(s) for s in splits])
    addSplits(client(session), handle(session), tablename, splitset)
end
table_merge(session::AccumuloSession, tablename::String, start_split, end_split) = mergeTablets(client(session), handle(session), tablename, bytes(start_split), bytes(end_split))
table_splits(session::AccumuloSession, tablename::String, max_splits::Integer=1024) = listSplits(client(session), handle(session), tablename, Int32(max_splits))

# Initiates a major compaction on tablets within the specified range that have one or more files.  If no file selection options are specified, then all files will be compacted.  Options that configure output
# settings are only applied to this compaction and not later compactions.  If multiple concurrent user initiated compactions specify iterators or a compaction strategy, then all but one will fail to start.
#function compact()
#end

# adds, deletes, or lists constraints for a table
constraints(session::AccumuloSession, tablename::String) = listConstraints(client(session), handle(session), tablename)
function add_constraints(session::AccumuloSession, tablename::String, names::String...)
    for name in names
        addConstraint(client(session), handle(session), tablename, name)
    end
end
function remove_constraints(session::AccumuloSession, tablename::String, ids::Integer...)
    for id in ids
        removeConstraint(client(session), handle(session), tablename, Int32(id))
    end
end

# flushes a tables data that is currently in memory to disk
flush(session::AccumuloSession, tablename::String; start_row=UInt8[], end_row=UInt8[], wait::Bool=true) = flushTable(client(session), handle(session), tablename, bytes(start_row), bytes(end_row), wait)

#=
# locality groups not supported yet
# gets the locality groups for a given table
function getgroups()
end

# sets the locality groups for a given table (for binary or commas, use Java API)
function setgroups()
end
=#
