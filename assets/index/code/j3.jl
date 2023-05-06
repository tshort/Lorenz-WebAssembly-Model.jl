# This file was generated, do not modify it. # hide
using StaticCompiler, StaticTools

compile_wasm(solv, 
    Tuple{typeof(integ), 
          MallocVector{Float64}, MallocVector{Float64}, 
          MallocVector{Float64}, MallocVector{Float64}}, 
    path = "_libs",
    flags = `--initial-memory=1048576 walloc.o`, filename = "julia_solv")