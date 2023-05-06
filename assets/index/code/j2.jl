# This file was generated, do not modify it. # hide
function solv(integ, tres, u1, u2, u3)
    for i in Int32(1):Int32(10000)
        @inline DiffEqGPU.step!(integ, integ.t + integ.dt, integ.u)
        tres[i] = integ.t
        u1[i] = integ.u[1]
        u2[i] = integ.u[2]
        u3[i] = integ.u[3]
    end
    nothing
end