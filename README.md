# Accumulo.jl

[Apache Accumulo](https://accumulo.apache.org/) is a database based on Google’s BigTable

Accumulo.jl is a client library for Apache Accumulo, built using the Accumulo Thrift Proxy API.

[![Build Status](https://travis-ci.org/JuliaDB/Accumulo.jl.svg?branch=master)](https://travis-ci.org/JuliaDB/Accumulo.jl)

## Connecting

To connect to the server, create an instance of AccumuloSession.

````
session = AccumuloSession()
````

Without any parameters, this attempts to connect to a server running on `localhost` port `42424`.
A remote server can be connected to by specifying the hostname and port number.

````
session = AccumuloSession("localhost", 42424)
````

As of now only SASL-Plain authentication is supported, without any `qop`. The default implementation
authenticates with the same user-id as that of the login shell. That can be overridden by providing
an appropriate instance of `AccumuloAuth`.

````
session = AccumuloSession("localhost", 42424, AccumuloAuthSASLPlain("uid", "pwd", "zid"))
````

The thrift `TCompactProtocol` is used by default, which is also the default for the server setup.
Other protocols can be used by specifying the optional named parameter `tprotocol`.
As of now, `:binary` and `:compact` protocols are supported.

````
session = AccumuloSession("localhost", 10000; tprotocol=:compact)
````

## Tables

All tables in a setup can be listed with a call to `tables(session)`.

Existence of a particular table can be checked with `table_exists(session, tablename)`

Row/column identifiers and cell data are treated as raw bytes.
Any type that can be converted to bytes can be used wherever row/column identifiers or values are expected in the APIs.
Since Julia already includes this `convert` method for strings, they can be used as it is. Any other type can also get the same treatment by defining either of
the following two methods:

- `convert(Vector{UInt8}, r)`
- `bytes(r)`


### Creating / Deleting

A table can be created, deleted or renamed by calling the corresponding function passing the table name.

````
table_create(session, tablename; versioning=true, logical_timestamp=false)
table_delete(session, tablename)
table_rename(session, tablename)
````

By default, tables are configured to use the `VersioningIterator` and keep one version.
The version policy can be changed by changing the `VersioningIterator` options with the `table_config!` function.

Using logical timestamps ensures timestamps always move forward. Though the actual millisecond time will not be used anymore, with this, tablet servers need not 
be time synchronized pefectly and multile updates at the same millisecond do not cause any issue.


### Cloning

A table can be cloned with:

````
table_clone(session, tablename, newtablename; flush=true, 
            set_properties=Dict(), exclude_properties=())
````

If the flush option is not enabled, then any data the source table currently has in memory will not exist in the clone.
A cloned table copies the configuration of the source table. However the permissions of the source table are not copied to the clone.
After a clone is created, only the user that created the clone can read and write to it.



### Configuration

To get or set table specific properties:

````
table_config(session, tablename)
table_config!(session, tablename, property::AbstractString, value::AbstractString)
````

`table_versions!` changes the number of versions the `VersioningIterator` keeps.

`table_versions!(session, tablename, nversions::Integer)`

`table_du` prints how much space, in bytes, is used by files referenced by a table. When multiple tables are specified it prints how much space, in bytes, is used by files shared between tables, if any.

`table_du(session, tables::AbstractString...)`


### Constraints

Constraints are applied on mutations at insert time and only those that satify them are allowed.
Constraints must be implemented as a Java class and included in Accumulo classpath.

````
# list constraints as a map of the class name and an integer ID
constraints(session, tablename)

# add and remove constraints
add_constraints(session, tablename, names::AbstractString...)
remove_constraints(session, tablename, ids::Integer...)
````

### Splits

Tablets constituting a table are automatically split based on a size threshold configurable per table.
Tablets can also be manually split or merged through the following APIs to tweak performance.
Split points are specified as row values.

````
# list current splits (upto max_splits)
table_splits(session, tablename, max_splits=1024)

# manually split / merge tablets
table_split(session, tablename, splits...)
table_merge(session, tablename, start_split, end_split)
````

### Exporting / Importing 

Tables can be moved across clusters by exporting them from the source, copying them via the hadoop `distcp` command, and importing them at the destination.
Exporting and importing tables preserves the tables configuration, splits, and logical time.

````
table_export(session, tablename, export_dir::AbstractString)
table_import(session, tablename, import_dir::AbstractString)
````

Table must be kept offline during an export while discp runs (to prevent files from being deleted).
A table can be cloned and the clone taken offline to be able to access the table during an export.

````
table_offline(session, tablename; wait=true)
table_online(session, tablename; wait=true)
````

## Iterators

Iterators are executed by Accumulo while scanning or compacting tables. They are a way of doing distributed operations on tables.
Iterators must be implemented as a Java class and included in Accumulo classpath.
They can be configured to be used during scanning or compaction events. The `IteratorScope` enum lists allowed scopes.

````
# list all iterators as a dict of class name and the scopes registered
iters(session, tablename)

# retrieve a single matching iterator with its setting
iter(session, tablename, itername::AbstractString, scope::Integer)
````

The below APIs allow configuring iterators for a table.

````
# create an iterator setting
iter(name, class, priority::Integer, properties::Dict=Dict())

# verify whether the iterator settings will be valid when applied on a table
check_iter(session, tablename, iter_setting::IteratorSetting, scopes)

# add or remote iterators configured on a table
add_iter(session, tablename, iter_setting::IteratorSetting, scopes; check=true)
remove_iter(session, tablename, iter_setting::IteratorSetting, scopes)
remove_iter(session, tablename, iter_name::AbstractString, scopes)

````

## Writing

Data is written to tables as batches of updates.

````
# initialize a batch
updates = batch()

# add mutations to the batch
update(updates, row, col_family, col_qualifier, col_visibility, value, timestamp::Integer=time_ms())
delete(updates, row, col_family, col_qualifier)

# update table
update(session, tablename, updates)
````

Updates can also be conditional. A condition is created using `where`.

````
# initialize a conditional batch
updates = conditional_batch()

# add a condition; comparing values, timestamps and also running additional iterators to evaluate complex conditions
where(updates, row, col_family, col_qualifier, col_visibility; value=nothing, timestamp=-1, iterators=IteratorSetting[])

# add mutations
update(updates, row, col_family, col_qualifier, col_visibility, value, timestamp::Integer=time_ms())
delete(updates, row, col_family, col_qualifier)

# update the table
update(session, tablename, updates)
````

Multiple batch updates can be applied by first obtaining a table writer.

````
batch_writer(session, tablename) do writer
    for i in 1:10
        updates = batch()
        for rownum in 1:N
            update(upd, "row$rownum", "colf", "colq", "", "value$rownum")
        end
        update(writer, upd)
        flush(writer)
    end
end
````

And similarly for conditional updates:

````
conditional_batch_writer(session, tablename) do writer
    for i in 1:10
        upd = conditional_batch()
        for rownum in 1:N
            row = "row$rownum"
            val = "value$rownum"
            update(where(upd, row, "colf", "colq"; value=val), "colf", "colq", "", "newvalue$rownum")
        end
        update(writer, upd)
        flush(writer)
    end
end
```` 

## Reading

Data can be read from tables using a scanner and iterating over the records.

````
# create a scanner
scanner(session, tablename) do scan
    # iterate over the records
    for rec in records(scan)
        # each record has key and value
        key = rec.key
        val = rec.value

        # the key consists of the row and column identifiers
        row = key.row
        colfam = key.colFamily
        colqual = key.colQualifier
        colvis = key.colVisibility

        # ...
    end
end
````

Only a subset of the columns can be fetched by specifying the list of columns as:

````
scanner(session, tablename; columns=[("colfam1","colqual1"), ("colfam2","colqual2")])
````

Additional iterators can be specified to be used with the scanner:

````
# iterator settings
iter1 = iter(name, class, priority::Integer, properties::Dict=Dict())
iter2 = iter(name, class, priority::Integer, properties::Dict=Dict())

# specify additional iterators to be used
scanner(session, tablename; iterators=[iter1, iter2])
````

The scanner can be restricted to only a single row or a subset of matching rows by specifying a range of keys to iterate over.

````
# assign appropriate key or range of keys to rng
scanner(session, tablename; rng=:())
````

A scanner key can be created using:

````
scanner_key(row; col_family="", col_qualifier="", col_visibility="", timestamp=0x7FFFFFFFFFFFFFFF)
````

A range of keys can be specified as expressions of the form `k1 <= x < k2` where:
- `k1` and `k2` are the bounds. They can either be just the row value, or a key created using `scanner_key`
- `<=`, `<`, `>`, `>=` help specify the lower and upper bounds and their inclusivity
- `x` is just any symbol to complete the expression syntax

The range bounds (`k1` and `k2` above) can be one of the following:
- just the row (bytes or type that can be converted to bytes)
- a key created by `scanner_key`
- an expression that evaluates to one of the above


## TODO:

- suppport for
    - table compactions
    - locality groups
    - namespaces
- additional authentication methods
- nicer API
