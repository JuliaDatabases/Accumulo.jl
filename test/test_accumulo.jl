using Accumulo
using Base.Test

const SEP = "\n" * "="^20 * "\n"
print_header(message) = println(SEP, message, SEP)

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

        cfg = table_config(session, tbl)
        println("Configuration of $tbl:")
        for (n,v) in cfg
            println("\t$n => $v")
        end

        tblconstr = constraints(session, tbl)
        println("Constraints on $tbl: $tblconstr")

        tbliters = iters(session, tbl)
        println("Iterators on $tbl: $tbliters")

        for (iname, iscopes) in tbliters
            for iscope in iscopes
                iprops = iter(session, tbl, iname, iscope)
                println("Iterator $iname on $tbl in scope $iscope: $iprops")
            end
        end
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

function test_table_write(session)
    print_header("TABLE WRITE")
    try
        println("creating mytable...")
        @test !table_exists(session, "mytable")
        table_create(session, "mytable")
        @test table_exists(session, "mytable")

        println("creating writer...")
        batch_writer(session, "mytable") do writer
            println("\tstarting batch...")
            upd = batch()
            println("\tcollecting mutations...")
            for rownum in 1:100
                update(upd, "row$rownum", "colf", "colq", "public", "value$rownum")
            end
            println("\tupdating mutations...")
            update(writer, upd)
            println("\tflushing writer...")
            flush(writer)
        end
        println("closed writer")

        println("creating conditional batch writer...")
        conditional_batch_writer(session, "mytable") do writer
            println("\tstarting batch...")
            upd = conditional_batch()
            println("\tcollecting mutations...")
            for rownum in 1:100
                row = "row$rownum"
                val = "value$rownum"
                update(where(upd, row, "colf", "colq", "public"; value=val), "colf", "colq", "public", "newvalue$rownum")
            end
            println("\tupdating mutations...")
            update(writer, upd)
            println("\tflushing writer...")
            flush(writer)
        end
        println("closed writer")

        println("creating writer for deletes...")
        batch_writer(session, "mytable") do writer
            println("\tstarting batch...")
            upd = batch()
            println("\tcollecting mutations...")
            for rownum in 1:100
                delete(upd, "row$rownum", "colf", "colq")
            end
            println("\tupdating mutations...")
            update(writer, upd)
            println("\tflushing writer...")
            flush(writer)
        end
        println("closed writer")
    finally
        println("cleaning up...")
        table_exists(session, "mytable") && table_delete(session, "mytable")
    end
end

session = AccumuloSession("127.0.1.1", 42424, AccumuloAuthSASLPlain("root", "root"))
print_info(session)
test_table_admin(session)
test_table_write(session)
close(session)

