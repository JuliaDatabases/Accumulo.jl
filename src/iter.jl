# lists table-specific iterators
iters(session::AccumuloSession, tablename::String) = listIterators(client(session), handle(session), tablename)

# get a single iterator with its settings
iter(session::AccumuloSession, tablename::String, itername::String, scope::Integer) = getIteratorSetting(client(session), handle(session), tablename, itername, Int32(scope))

# create an iterator type
function iter(name::String, class::String, priority::Integer, properties::Dict=Dict())
    iter_properties = Dict{String,String}(string(n)=>string(v) for (n,v) in properties)

    thriftbuild(IteratorSetting, Dict(:priority => Int32(priority),
        :name => name,
        :iteratorClass => class,
        :properties => iter_properties))
end

# attach an iterator to a table
function add_iter(session::AccumuloSession, tablename::String, iter_setting::IteratorSetting, scopes::SET; check::Bool=true)
    iter_scopes = Set([Int32(scope) for scope in scopes])

    if check
        checkIteratorConflicts(client(session), handle(session), tablename, iter_setting, iter_scopes)
    end
    attachIterator(client(session), handle(session), tablename, iter_setting, iter_scopes)
end

# detach the iterator from the table
remove_iter(session::AccumuloSession, tablename::String, iter_setting::IteratorSetting, scopes::SET) = remove_iter(session, tablename, iter_setting.name, scopes)
function remove_iter(session::AccumuloSession, tablename::String, name::String, scopes::SET)
    iter_scopes = Set([Int32(scope) for scope in scopes])
    removeIterator(client(session), handle(session), tablename, iter_scopes)
end

# check if there is any conflicts with the iterator name and priority
function check_iter(session::AccumuloSession, tablename::String, iter_setting::IteratorSetting, scopes::SET)
    iter_scopes = Set([Int32(scope) for scope in scopes])
    checkIteratorConflicts(client(session), handle(session), tablename, iter_setting, iter_scopes)
end
