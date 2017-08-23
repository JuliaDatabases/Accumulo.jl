using Accumulo
using Base.Test

const SEP = "\n" * "="^20 * "\n"
print_header(message) = println(SEP, message, SEP)

function print_table_config(session, tbl)
    cfg = table_config(session, tbl)
    println("Configuration of $tbl:")
    for (n,v) in cfg
        println("\t$n => $v")
    end
end

function print_table_iters(session, tbl)
    tbliters = iters(session, tbl)
    println("Iterators on $tbl: $tbliters")

    for (iname, iscopes) in tbliters
        for iscope in iscopes
            iprops = iter(session, tbl, iname, iscope)
            println("Iterator $iname on $tbl in scope $iscope: $iprops")
        end
    end
end

function print_info(session)
    print_header("SERVER INFO")
    tbls = tables(session)
    println("Tables: $tbls")

    diskusage = table_du(session, tbls...)
    println("Disk updage of $tbls: $diskusage")

    for tbl in tbls
        println("Table: $tbl")
        println("===========================")

        diskusage = table_du(session, tbl)
        println("Disk updage of $tbl: $diskusage")

        print_table_config(session, tbl)
        print_table_iters(session, tbl)

        tblconstr = constraints(session, tbl)
        println("Constraints on $tbl: $tblconstr")
    end
end

function test_table_admin(session)
    print_header("TABLE ADMIN")
    try
        println("creating mytable...")
        @test !table_exists(session, "mytable")
        table_create(session, "mytable")
        @test table_exists(session, "mytable")

        println("renaming mytable to mytable1...")
        table_rename(session, "mytable", "mytable1")
        @test table_exists(session, "mytable1")
        @test !table_exists(session, "mytable")

        println("cloning mytable1 to mytable2...")
        table_clone(session, "mytable1", "mytable2")
        @test table_exists(session, "mytable2")
       
        println("deleting mytable1...")
        table_delete(session, "mytable1")
        @test !table_exists(session, "mytable1")
        @test table_exists(session, "mytable2")

        println("deleting mytable2...")
        table_delete(session, "mytable2")
        @test !table_exists(session, "mytable2")
    finally
        for tbl in ("mytable", "mytable1", "mytable2")
            println("cleaning up $tbl...")
            table_exists(session, tbl) && table_delete(session, tbl)
        end
    end
end

function test_table_readwrite(session)
    N = 10
    TNAME = "mytable"

    function _scan_verify(valpfx)
        println("creating scanner...")
        scanner(session, TNAME) do scan
            println("\tstarting iteration...")
            nrecs = 0
            for rec in records(scan)
                row = String(copy(rec.key.row))
                colfam = String(copy(rec.key.colFamily))
                colqual = String(copy(rec.key.colQualifier))
                colvis = String(copy(rec.key.colVisibility))
                val = String(copy(rec.value))
                println("\trow($(row)), column($(colfam):$(colqual)), visibility($(colvis)), value($(val))")
                rownum = parse(Int, row[4:end])
                @test colfam == "colf"
                @test colqual == "colq"
                @test colvis == ""
                if isempty(valpfx)
                    @test val == ""
                else
                    @test val == "$valpfx$rownum"
                end
                nrecs += 1
            end
            println("\tfinished iteration ($nrecs records)...")
        end
        println("closed scanner")
    end

    function _create()
        println("creating $TNAME...")
        @test !table_exists(session, TNAME)
        table_create(session, TNAME; versioning=false)
        @test table_exists(session, TNAME)
        table_versions!(session, TNAME, 1)
        #print_table_config(session, TNAME)
        #print_table_iters(session, TNAME)
    end

    function _write()
        println("creating writer...")
        batch_writer(session, TNAME) do writer
            println("\tstarting batch...")
            upd = batch()
            println("\tcollecting mutations...")
            for rownum in 1:N
                update(upd, "row$rownum", "colf", "colq", "", "value$rownum")
            end
            println("\tupdating mutations...")
            update(writer, upd)
            println("\tflushing writer...")
            flush(writer)
        end
        println("closed writer")
    end

    function _update()
        println("creating conditional batch writer...")
        conditional_batch_writer(session, TNAME) do writer
            println("\tstarting batch...")
            upd = conditional_batch()
            println("\tcollecting mutations...")
            for rownum in 1:N
                row = "row$rownum"
                val = "value$rownum"
                update(where(upd, row, "colf", "colq"; value=val), "colf", "colq", "", "newvalue$rownum")
                #update(where(upd, row, "colf", "colq", "public"; value=val), "colf", "colq", "public", "newvalue$rownum")
            end
            println("\tupdating mutations...")
            res = update(writer, upd)
            status_counts = Dict(ConditionalStatus.ACCEPTED => 0, ConditionalStatus.REJECTED => 0, ConditionalStatus.VIOLATED => 0, ConditionalStatus.UNKNOWN => 0, ConditionalStatus.INVISIBLE_VISIBILITY => 0)
            for v in values(res)
                status_counts[v] += 1
            end
            println("\tstatus counts: $status_counts")
            println("\tflushing writer...")
            flush(writer)
        end
        println("closed writer")
    end

    function _delete()
        println("creating writer for deletes...")
        batch_writer(session, TNAME) do writer
            println("\tstarting batch...")
            upd = batch()
            println("\tcollecting mutations...")
            for rownum in 1:N
                delete(upd, "row$rownum", "colf", "colq")
            end
            println("\tupdating mutations...")
            update(writer, upd)
            println("\tflushing writer...")
            flush(writer)
        end
        println("closed writer")
    end

    print_header("TABLE READ WRITE")
    try
        _create()
        _write()
        _scan_verify("value")
        _update()
        _scan_verify("newvalue")
        _delete()
        _scan_verify("")
    finally
        println("cleaning up...")
        table_exists(session, TNAME) && table_delete(session, TNAME)
    end
end

session = AccumuloSession("127.0.1.1", 42424, AccumuloAuthSASLPlain("root", "root"))
print_info(session)
test_table_admin(session)
test_table_readwrite(session)
close(session)

