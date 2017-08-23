const ScannerOptions = Union{ScanOptions, BatchScanOptions}

const DEFAULT_FETCH_SIZE = 1000

type Scanner{T <: ScannerOptions}
    session::AccumuloSession
    tablename::String
    scannername::String
    options::T
end

##
# Range defines a range of values for either the row or a column
# Ranges are specified as expressions of the form:
#   k1 <= x < k2
#   where:
#   - k1 and k2 are the bounds
#   - <=, <, >, >= help specify the lower and upper bounds and their inclusivity
#   - x is just any symbol to complete the expression syntax
#
# A range bounds is either just the row or a key created by `scanner_key`
scanner_key(k::Key) = k
function scanner_key(row; col_family=UInt8[], col_qualifier=UInt8[], col_visibility=UInt8[], timestamp::Integer=0x7FFFFFFFFFFFFFFF)
    k = thriftbuild(Key, Dict(:row => bytes(row),
            :colFamily => bytes(col_family),
            :colQualifier => bytes(col_qualifier),
            :colVisibility => bytes(col_visibility)))
    (timestamp == 0x7FFFFFFFFFFFFFFF) || set_field!(k, :timestamp, Int64(timestamp))
    k
end

const _incr = (:<, :<=)
const _decr = (:>, :>=)
const _incl = (:<=, :>=)
const _excl = (:<, :>)
function as_range(rng::Expr)
    args = rng.args

    if (args[2] in _incr) && (args[4] in _incr)
        start_row   = args[1]
        start_incl  = args[2] in _incl
        end_incl    = args[4] in _incl
        end_row     = args[5]
    elseif (args[2] in _decr) && (args[4] in _decr)
        end_row     = args[1]
        end_incl    = args[2] in _incl
        start_incl  = args[4] in _incl
        start_row   = args[5]
    else
        error("Unsupported row range syntax $rng")
    end

    start_key = scanner_key(eval(start_row))
    end_key = scanner_key(eval(end_row))

    thriftbuild(Accumulo.proxy.Range, Dict(:start => start_key,
        :startInclusive => start_incl,
        :stop => stop_key,
        :stopInclusive => stop_incl))
end

function as_col(colspec)
    col = ScanColumn()
    if isa(colspec, Tuple)
        set_field!(col, :colFamily, bytes(colspec[1]))
        (length(colspec) > 1) && set_field!(col, :colQualifier, bytes(colspec[2]))
    else
        set_field!(col, :colFamily, bytes(colspec))
    end
    col
end

function scanner_opts(;rng::Union{Expr,SET} = :(),
                columns::Vector = Tuple[],
                iterators::Vector{IteratorSetting} = IteratorSetting[],
                authorizations::SET = (),
                buffer_size::Integer = 0,
                threads::Integer = 0)
    if isa(rng, Expr)
        opts = ScanOptions()
        isempty(rng.args) || set_field!(opts, :range, as_range(rng))
        (buffer_size > 0) && set_field!(opts, :bufferSize, buffer_size)
    else
        opts = BatchScanOptions()
        isempty(rngs) || set_field!(opts, :ranges, [as_range(rng) for rng in rngs])
        (threads > 0) && set_field!(opts, :threads, threads)
    end

    isempty(authorizations) || set_field!(opts, :authorizations, Set([bytes(x) for x in authorizations]))
    (length(columns) > 0) && set_field!(opts, :columns, [as_col(colspec) for colspec in columns])
    isempty(iterators) || set_field!(opts, :iterators, iterators)
    opts
end

function scanner(session::AccumuloSession, tablename::String;
                rng::Union{Expr,SET} = :(),
                columns::Vector = Tuple[],
                iterators::Vector{IteratorSetting} = IteratorSetting[],
                authorizations::SET = (),
                buffer_size::Integer = 0,
                threads::Integer = 0)
    opts = scanner_opts(;rng=rng, columns=columns, iterators=iterators, authorizations=authorizations, buffer_size=buffer_size, threads=threads)
    scanner(session, tablename, opts)
end

function scanner(session::AccumuloSession, tablename::String, opts::ScanOptions)
    scanhandle = createScanner(client(session), handle(session), tablename, opts)
    Scanner(session, tablename, scanhandle, opts)
end

function scanner(session::AccumuloSession, tablename::String, opts::BatchScanOptions)
    scanhandle = createBatchScanner(client(session), handle(session), tablename, opts)
    Scanner(session, tablename, scanhandle, opts)
end

function scanner(f::Function, args...; kwargs...)
    s = scanner(args...; kwargs...)
    try
        f(s)
    finally
        close(s)
    end
end

close(scanner::Scanner) = closeScanner(client(scanner.session), scanner.scannername)
eof(scanner::Scanner) = !hasNext(client(scanner.session), scanner.scannername)


type RecordIterator
    handle::Scanner
    fetchsize::Int32
    eof::Bool
    pos::Int
    records::Nullable{Vector{KeyValue}}

    function RecordIterator(scanner::Scanner; fetch_size::Integer=DEFAULT_FETCH_SIZE, check::Bool=true)
        iseof = check ? eof(scanner) : false
        new(scanner, Int32(fetch_size), iseof, 1, Nullable{Vector{KeyValue}}())
    end
end

records(scanner::Scanner; fetch_size::Integer=DEFAULT_FETCH_SIZE) = RecordIterator(scanner; fetch_size=fetch_size)

start(it::RecordIterator) = it.eof
done(it::RecordIterator, state) = state
function next(it::RecordIterator, state)
    if isnull(it.records) || (it.pos > length(get(it.records)))
        result = nextK(client(it.handle.session), it.handle.scannername, it.fetchsize)
        recs = result.results
        it.records = Nullable(recs)
        it.pos = 1
        it.eof = !result.more
    else
        recs = get(it.records)
    end
    rec = recs[it.pos]
    it.pos += 1
    rec, (it.eof && (it.pos > length(recs)))
end
