# This file was generated, do not modify it. # hide
using DiffEqGPU, StaticArrays, OrdinaryDiffEq

function lorenz(u, p, t)
    σ = p[1]
    ρ = p[2]
    β = p[3]
    du1 = σ * (u[2] - u[1])
    du2 = u[1] * (ρ - u[3]) - u[2]
    du3 = u[1] * u[2] - β * u[3]
    return SVector{3}(du1, du2, du3)
end

u0 = @SVector [1.0; 0.0; 0.0]
tspan = (0.0, 20.0)
p = @SVector [10.0, 28.0, 8 / 3.0]
prob = ODEProblem{false}(lorenz, u0, tspan, p)

integ = DiffEqGPU.gputsit5_init(GPUTsit5(), lorenz, false, u0, 0.0, 0.005, p, nothing, CallbackSet(nothing), true, false)