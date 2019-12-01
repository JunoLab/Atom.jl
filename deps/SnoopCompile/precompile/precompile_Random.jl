function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    precompile(Tuple{typeof(Random._rand_max383!), Random.MersenneTwister, Random.UnsafeView{Float64}, Random.CloseOpen01{Float64}})
    precompile(Tuple{typeof(Random.DSFMT.dsfmt_fill_array_close_open!), Random.DSFMT.DSFMT_state, Ptr{Float64}, Int64})
    precompile(Tuple{typeof(Random.shuffle!), Random.MersenneTwister, Array{Symbol, 1}})
    precompile(Tuple{typeof(Random.rand!), Random.MersenneTwister, Random.UnsafeView{Float64}, Random.SamplerTrivial{Random.CloseOpen01{Float64}, Float64}})
    precompile(Tuple{typeof(Random.default_rng)})
    precompile(Tuple{typeof(Random.seed!), Array{UInt32, 1}})
end
