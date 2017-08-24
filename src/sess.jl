##
# Authentication mechanisms
# Only SASL-Plain supported for now
type AccumuloAuth
    mechanism::String
    callback::Function

    AccumuloAuth(mechanism::String=SASL_MECH_PLAIN, callback::Function=Thrift.sasl_callback_default) = new(mechanism, callback)
end

function AccumuloAuthSASLPlain(uid::String, passwd::String; zid::String="")
    function callback(part::Symbol)
        (part == :authcid) && (return uid)
        (part == :passwd) && (return passwd)
        (part == :show) && (return uid)
        (part == :mechanism) && (return "SASL-Plain")
        return zid
    end
    AccumuloAuth(SASL_MECH_PLAIN, callback)
end

function show(io::IO, auth::AccumuloAuth)
    uid = auth.callback(:show)
    mech = auth.callback(:mechanism)
    println(io, "AccumuloAuth ($mech): $uid")
    nothing
end

##
# AccumuloConn holds the thrift connection and protocol objects.
# It also holds the accumulo session handle for this connection.
type AccumuloConn
    transport::TTransport
    protocol::TProtocol
    client::AccumuloProxyClient
    handle::Vector{UInt8}
    connstr::String

    function AccumuloConn(host::String, port::Integer, auth::AccumuloAuth; tprotocol::Symbol=:compact)
        transport = TFramedTransport(TSocket(host, port))
        if tprotocol === :binary
            protocol = TBinaryProtocol(transport, true)
        elseif tprotocol === :compact
            protocol = TCompactProtocol(transport)
        else
            error("Unsupported protocol: $tprotocol")
        end
        client = AccumuloProxyClient(protocol)
        uid = auth.callback(:show)
        connstr = "accumulo://$(uid)@$(host):$port"
        new(transport, protocol, client, connect(transport, client, auth), connstr)
    end

    function connect(transport::TTransport, client::AccumuloProxyClient, auth::AccumuloAuth)
        open(transport)
        uid = auth.callback(:authcid)
        creds = Dict{String,String}("password" => auth.callback(:passwd))
        login(client, uid, creds)
    end
end

function show(io::IO, conn::AccumuloConn)
    println(io, conn.connstr)
    nothing
end

function close(conn::AccumuloConn)
    close(conn.transport)
    nothing
end

#
# AccumuloSession holds a connection and session status
type AccumuloSession
    conn::AccumuloConn

    function AccumuloSession(host::String="localhost", port::Integer=42424, auth::AccumuloAuth=AccumuloAuth(); tprotocol::Symbol=:compact)
        new(AccumuloConn(host, port, auth; tprotocol=tprotocol))
    end
end

function show(io::IO, sess::AccumuloSession)
    print(io, "AccumuloSession: ")
    show(io, sess.conn)
end
close(session::AccumuloSession) = close(session.conn)
client(session::AccumuloSession) = session.conn.client
handle(session::AccumuloSession) = session.conn.handle

