const SET = Union{Set,Vector,Tuple}

bytes(r) = convert(Vector{UInt8}, r)

time_ms() = round(Int64, time() * 1000)
