const DEFAULT_MAX_MEMORY = 50 * 1024 * 1024
const DEFAULT_MAX_LATENCY = 2 * 60 * 1000
const DEFAULT_TIMEOUT = typemax(Int64)
const DEFAULT_MAX_WRITE_THREADS = 3

function _col_delete(col_family, col_qualifier)
    thriftbuild(ColumnUpdate, Dict(:colFamily => bytes(col_family),
        :colQualifier => bytes(col_qualifier),
        :deleteCell => true))
end

function _col_update(col_family, col_qualifier, col_visibility, value, timestamp::Integer=time_ms())
    thriftbuild(ColumnUpdate, Dict(:colFamily => bytes(col_family),
        :colQualifier => bytes(col_qualifier),
        :colVisibility => bytes(col_visibility),
        :timestamp => timestamp,
        :value => bytes(value)))
end

const ColumnUpdates         = Vector{ColumnUpdate}
const AbstractUpdate        = Union{ColumnUpdates, ConditionalUpdates}
const AbstractWriterOptions = Union{WriterOptions, ConditionalWriterOptions}

##
# BatchUpdates collect mutations to be applied with a batch operation
type BatchUpdates{T <: AbstractUpdate}
    mutations::Dict{Vector{UInt8}, T}
end
function (::Type{BatchUpdates{T}}){T}()
    BatchUpdates{T}(Dict{Vector{UInt8}, T}())
end

batch() = BatchUpdates{ColumnUpdates}()
conditional_batch() = BatchUpdates{ConditionalUpdates}()

function mutate{T<:ColumnUpdates}(upd::BatchUpdates{T}, row, action::ColumnUpdate)
    rowbytes = bytes(row)
    if rowbytes in keys(upd.mutations)
        mut = upd.mutations[rowbytes]
    else
        mut = upd.mutations[rowbytes] = ColumnUpdate[]
    end
    push!(mut, action)
    mut
end

function mutate{T<:ConditionalUpdates}(upd::BatchUpdates{T}, row, action::ColumnUpdate)
    rowbytes = bytes(row)
    if rowbytes in keys(upd.mutations)
        cu = upd.mutations[rowbytes]
    else
        cu = upd.mutations[rowbytes] = ConditionalUpdates()
    end
    mutate(cu, action)
end

function mutate(cu::ConditionalUpdates, condition::ColumnUpdate)
    isfilled(cu, :updates) || set_field!(cu, :updates, ColumnUpdate[])
    push!(cu.updates, condition)
    cu
end

function mutate{T<:ConditionalUpdates}(upd::BatchUpdates{T}, row, condition::Accumulo.proxy.Condition)
    rowbytes = bytes(row)
    if rowbytes in keys(upd.mutations)
        cu = upd.mutations[rowbytes]
    else
        cu = upd.mutations[rowbytes] = ConditionalUpdates()
    end
    mutate(cu, condition)
end

function mutate(cu::ConditionalUpdates, condition::Accumulo.proxy.Condition)
    isfilled(cu, :conditions) || set_field!(cu, :conditions, Accumulo.proxy.Condition[])
    push!(cu.conditions, condition)
    cu
end

# returns a Condition type
function where{T<:ConditionalUpdates}(upd::BatchUpdates{T}, row, col_family, col_qualifier, col_visibility=UInt8[]; value=nothing, timestamp::Integer=-1, iterators::Vector{IteratorSetting}=IteratorSetting[])
    col = thriftbuild(Column, Dict(:colFamily => bytes(col_family),
            :colQualifier => bytes(col_qualifier),
            :colVisibility => bytes(col_visibility)))

    cond = Accumulo.proxy.Condition()
    set_field!(cond, :column, col)

    (value === nothing) || set_field!(cond, :value, bytes(value))
    (timestamp < 0)     || set_field!(cond, :timestamp, Int64(timestamp))
    isempty(iterators)  || set_field!(cond, :iterators, iterators)

    mutate(upd, row, cond)
end

update{T}(upd::BatchUpdates{T}, row, col_family, col_qualifier, col_visibility, value, timestamp::Integer=time_ms()) = mutate(upd, row, _col_update(col_family, col_qualifier, col_visibility, value, timestamp))
delete{T}(upd::BatchUpdates{T}, row, col_family, col_qualifier) = mutate(upd, row, _col_delete(col_family, col_qualifier))
update(cu::ConditionalUpdates, col_family, col_qualifier, col_visibility, value, timestamp::Integer=time_ms()) = mutate(cu, _col_update(col_family, col_qualifier, col_visibility, value, timestamp))
delete(cu::ConditionalUpdates, col_family, col_qualifier) = mutate(cu, _col_delete(col_family, col_qualifier))


type BatchWriter{T <: AbstractWriterOptions}
    session::AccumuloSession
    tablename::String
    writername::String
    options::T
end

function batch_writer(session::AccumuloSession, tablename::String;
            max_memory::Integer=DEFAULT_MAX_MEMORY, latency_ms::Integer=DEFAULT_MAX_LATENCY,
            timeout_ms::Integer=DEFAULT_TIMEOUT, threads::Integer=DEFAULT_MAX_WRITE_THREADS,
            durability::Integer=Durability.DEFAULT)
    opts = thriftbuild(WriterOptions, Dict(:maxMemory => Int64(max_memory),
                :latencyMs => Int64(latency_ms),
                :timeoutMs => Int64(timeout_ms),
                :threads => Int32(threads),
                :durability => Int32(durability)))
    tbl = tablename
    writer = createWriter(client(session), handle(session), tbl, opts)
    BatchWriter(session, tbl, writer, opts)
end

function batch_writer(f::Function, args...; kwargs...)
    w = batch_writer(args...; kwargs...)
    try
        f(w)
    finally
        close(w)
    end
end

function conditional_batch_writer(session::AccumuloSession, tablename::String;
            max_memory::Integer=-1, timeout_ms::Integer=DEFAULT_TIMEOUT,
            threads::Integer=DEFAULT_MAX_WRITE_THREADS, authorizations::SET=[],
            durability::Integer=Durability.DEFAULT)
    opts = ConditionalWriterOptions()
    (max_memory < 0) || set_field!(opts, :maxMemory, Int64(max_memory))
    (timeout_ms < 0) || set_field!(opts, :timeoutMs, Int64(timeout_ms))
    (threads < 0) || set_field!(opts, :threads, Int32(threads))
    if !isempty(authorizations)
        auths = Set([bytes(x) for x in authorizations])
        set_field!(opts, :authorizations, auths)
    end
    (durability == Durability.DEFAULT) || set_field!(opts, :durability, Int32(durability))

    tbl = tablename
    writer = createConditionalWriter(client(session), handle(session), tbl, opts)
    BatchWriter(session, tbl, writer, opts)
end

function conditional_batch_writer(f::Function, args...; kwargs...)
    w = conditional_batch_writer(args...; kwargs...)
    try
        f(w)
    finally
        close(w)
    end
end

close(writer::BatchWriter{WriterOptions}) = closeWriter(client(writer.session), writer.writername)
close(writer::BatchWriter{ConditionalWriterOptions}) = closeConditionalWriter(client(writer.session), writer.writername)

flush(writer::BatchWriter{WriterOptions}) = flush(client(writer.session), writer.writername)
flush(writer::BatchWriter{ConditionalWriterOptions}) = nothing  # there's no flush API for conditional writes. this function just exists for uniformity

update(writer::BatchWriter{WriterOptions}, mutations::BatchUpdates{ColumnUpdates}) = update(client(writer.session), writer.writername, mutations.mutations)
update(writer::BatchWriter{ConditionalWriterOptions}, mutations::BatchUpdates{ConditionalUpdates}) = updateRowsConditionally(client(writer.session), writer.writername, mutations.mutations)

update(session::AccumuloSession, tablename::String, mutations::BatchUpdates{ColumnUpdates}) = updateAndFlush(client(session), handle(session), tablename, mutations.mutations)
function update(session::AccumuloSession, tablename::String, upd::BatchUpdates{ConditionalUpdates})
    results = Dict{Vector{UInt8}, ConditionalStatus}()
    for (row, cu) in upd.mutations
        result = updateRowConditionally(client(session), handle(session), tablename, row, cu)
        results[row] = result
    end
    results
end
