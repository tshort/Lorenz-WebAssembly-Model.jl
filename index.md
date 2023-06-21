\begin{section}{}
~~~<div id="mdpad"></div></div>
~~~
\end{section}

\begin{section}{title="WebAssembly"}

This is an attempt to compile a model with [OrdinaryDiffEq](https://github.com/SciML/OrdinaryDiffEq.jl). See [this app](../Lorenz-WebAssembly-Model.jl/) for an approach using [DiffEqGPU](https://github.com/SciML/DiffEqGPU.jl), which is naturally more amenable to static compilation. That app has more explanations of how this app was built. 

Here is the model with initial conditions that we'll compile. 

```julia:j1
using StaticArrays, OrdinaryDiffEq

function lorenz(u, p, t)
    σ = p[1]
    ρ = p[2]
    β = p[3]
    du1 = σ * (u[2] - u[1])
    du2 = u[1] * (ρ - u[3]) - u[2]
    du3 = u[1] * u[2] - β * u[3]
    return SVector{3}(du1, du2, du3)
end

u0 = @SVector [1.0; 0.01; 0.01]
tspan = (0.0, 20.0)
p = @SVector [10.0, 28.0, 8 / 3.0]
prob = ODEProblem{false}(lorenz, u0, tspan, p)

integ = init(prob, Tsit5(), adaptive = false, dt = 0.005)
integ.dt = 0.005
@show integ.opts
```

Before we can use the integrator `integ`, we need to create a modified version of this that works better with static compilation. We're trying to create a new integrator with fields that are amenable to static compilation. This uses Accessors.jl to transform an object. In particular, we need to change `integ.k` from an Array to a MallocArray. The `ODEIntegrator` does not provide an easy constructor, so `@set` doesn't work without defining a complicated `ConstructionBase.constructorof` function. 

```julia:j1a
using StaticTools
using DataStructures

struct DiffEqCtx <: DefaultStaticContext end
StaticTools.static_type(ctx::DiffEqCtx, x::ODEProblem) = x
StaticTools.static_type(ctx::DiffEqCtx, ::Type{T}) where T <: ODEProblem  = T

StaticTools.static_type(ctx::DiffEqCtx, ::Type{<:DataStructures.BinaryHeap}) = Int
StaticTools.static_type(ctx::DiffEqCtx, x::DataStructures.BinaryHeap) = 99

## The following doesn't work because the constructor leaves off two parameters at the end
# integ2 = static_type(integ)

newtypes, newfields = static_type_contents(DiffEqCtx(), integ)
integ2 = typeof(integ).name.wrapper{newtypes...}(newfields[1:end-2]...)

using Accessors
using ConstructionBase
ConstructionBase.constructorof(::Type{T}) where {T<:typeof(integ)} =
    (sol, u, du, k, t, dt, 
     f, p, uprev, uprev2, duprev, tprev, 
     alg, dtcache, dtchangeable, dtpropose, tdir, eigen_est, 
     EEst, qold, q11, erracc, dtacc, success_iter, 
     iter, saveiter, saveiter_dense, cache, callback_cache, kshortsize, 
     force_stepfail, last_stepfail, just_hit_tstop, do_error_check, event_last_time, vector_event_last_time, 
     last_event_error, accept_step, isout, reeval_fsal, u_modified, reinitialize, 
     isdae, opts, stats, initializealg, fsalfirst, fsallast) ->
    OrdinaryDiffEq.ODEIntegrator{
        typeof(alg), isinplace(sol.prob), typeof(u), typeof(du),
        typeof(t), typeof(p),
        typeof(eigen_est), typeof(EEst),
        typeof(qold), typeof(tdir), typeof(k), typeof(sol),
        typeof(f), typeof(cache),
        typeof(opts), typeof(fsalfirst),
        typeof(last_event_error), typeof(callback_cache),
        typeof(initializealg)}(
            sol, u, du, k, t, dt, 
            f, p, uprev, uprev2, duprev, tprev, 
            alg, dtcache, dtchangeable, dtpropose, tdir, eigen_est, 
            EEst, qold, q11, erracc, dtacc, success_iter, 
            iter, saveiter, saveiter_dense, cache, callback_cache, kshortsize, 
            force_stepfail, last_stepfail, just_hit_tstop, do_error_check, event_last_time, vector_event_last_time, 
            last_event_error, accept_step, isout, reeval_fsal, u_modified, reinitialize, 
            isdae, opts, stats, initializealg)

i3 = @set integ.k = MallocArray(integ.k)

```

Now, we can define a function to solve this model. We'll use `integ2` and manually step through the solution. `OrdinaryDiffEq.perform_step!` is very low level. It leaves out some significant features, including callbacks and adaptive stepping. Supporting more of [OrdinaryDiffEq.loopheader!](https://github.com/SciML/OrdinaryDiffEq.jl/blob/7f15be0dfa0375832de532972d732a6c475be71b/src/integrators/integrator_utils.jl#L6) and [OrdinaryDiffEq.loopfooter!](https://github.com/SciML/OrdinaryDiffEq.jl/blob/7f15be0dfa0375832de532972d732a6c475be71b/src/integrators/integrator_utils.jl#L200) would be an interesting exercise.

```julia:j2
function solv(integrator, tres, u1, u2, u3)
    @inbounds for i in Int32(1):Int32(10000)
        integrator.uprev = integrator.u
        @inline OrdinaryDiffEq.perform_step!(integrator, OrdinaryDiffEq.Tsit5ConstantCache())
        integrator.tprev = integrator.t
        integrator.t += integrator.dt
        integrator.last_stepfail = false
        integrator.accept_step = true
        integrator.dtpropose = integrator.dt
        tres[i] = integrator.t
        u1[i] = integrator.u[1]
        u2[i] = integrator.u[2]
        u3[i] = integrator.u[3]
    end
    integrator.uprev[1]
end
#function solv(integ, tres, u1, u2, u3)
#   #tres[1] = 99.0
#   #u1[1]
#   unsafe_trunc(Int32, length(tres))
#end
```

Now, we can compile `solv` to the WebAssembly file `_libs/julia_solv.wasm` using `StaticCompiler.compile_wasm`. `StaticTools.MallocVector` is used for the solution vectors. When compiling, `flags` are passed to the WebAssembly linker (`lld -flavor wasm`), and we can include the initial memory size and other files to link in. Initial memory must be big enough to hold objects we'll use.

```julia:j3
using StaticCompiler, StaticTools
# integ2 = i3

compile_wasm(((solv, 
    Tuple{typeof(integ),
          Vector{Float64}, Vector{Float64}, 
          Vector{Float64}, Vector{Float64}}),), 
    path = "_libs",
    flags = `--allow-undefined --unresolved-symbols=ignore-all --initial-memory=$(65536 * 20) walloc.o printf.o`, filename = "solv")
    # flags = `--unresolved-symbols=ignore-all --initial-memory=$(65536 * 20) walloc.o printf.o`, filename = "solv")
cp("_libs/obj.o", "_libs/obj.o.wasm", force=true)
```
\end{section}

\begin{section}{title="Interfacing"}

As before, we create JavaScript interfacing code for our integrator. "String" needed to be replaced because it was causing problems on the JavaScript side.

```julia:j4
using WebAssemblyInterfaces

integ_types = js_types(typeof(integ))
integ_def = js_def(integ)
integ_types = replace(integ_types, "String" => "JLString")
integ_def = replace(integ_def, "String" => "JLString")

println("<script>\n", integ_types, "\n\n")
println("function new_integ() {return ", integ_def, "\n}\n</script>")
```

\end{section}










~~~

<script src="wasm-printf.js"></script>
<script src="libs/mdpad/mdpad.js"></script>
<script src="libs/mdpad/mdpad-mithril.js"></script>
<script src="libs/wasm-ffi.browser.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/mithril/2.0.4/mithril.min.js"></script>
<script src="https://cdn.plot.ly/plotly-basic-1.54.1.min.js"></script>


~~~
{{ rawoutput j4 }}
~~~


<script>
const library = new ffi.Wrapper({
  solv: ['number', [ODEIntegrator, 
                    ffi.julia.Array('f64'), ffi.julia.Array('f64'),
                    ffi.julia.Array('f64'), ffi.julia.Array('f64')]],
}, {debug: true});

library.imports(wrap => ({
  env: {
    memory: new WebAssembly.Memory({ initial: 20 }),
    ...(printf.printf_env),
    ijl_bounds_error_ints: function() {}
  },
}));

var N = 10000
var t  = new ffi.julia.Array('f64', 1, new Float64Array(N))
var u1 = new ffi.julia.Array('f64', 1, new Float64Array(N))
var u2 = new ffi.julia.Array('f64', 1, new Float64Array(N))
var u3 = new ffi.julia.Array('f64', 1, new Float64Array(N))


async function mdpad_init() {
    var layout =
      m(".row",
        m(".col-md-3",
          m("br"),
          m("br"),
          m("form.form",
            minput({ title:"σ", mdpad:"p1", step:0.2, value:10.0 }),
            minput({ title:"ρ", mdpad:"p2", step:1.0, value:28.0 }),
            minput({ title:"β", mdpad:"p3", step:0.1, value:8 / 3 }),
           )),
        m(".col-md-1"),
        m(".col-md-8",
          m("#results"),
          m("#plot1", {style:"max-width:500px"})),
      m(".row",
        m(".col-md-1"),
        m(".col-md-8",
          m("#plot2"))))
    await m.render(document.querySelector("#mdpad"), layout);
    await library.fetch('libs/solv.wasm')
    printf.printf_init(library.exports.memory)
}
//    integ = new_integ();

function mdpad_update() {
    var integ = new_integ();
    integ.p.data = [mdpad.p1, mdpad.p2, mdpad.p3];
    console.log(library.solv(integ, t, u1, u2, u3));

    integ.free();
    tdata = [{x: t.values, y: u1.values, type: "line", name: "x"}, 
            {x: t.values, y: u2.values, type: "line", name: "y"}, 
            {x: t.values, y: u3.values, type: "line", name: "z"}] 
    tplot = mplotly(tdata, { width: 900, height: 300, margin: { t: 20, b: 20 }}, {responsive: true})
    m.render(document.querySelector("#plot2"), tplot)
    xydata = [{x: u1.values, y: u2.values, type: "line", name: "x"}] 
    xyplot = mplotly(xydata, { width: 400, height: 400, margin: { t: 20, b: 20, l: 20, r: 20 }}, {responsive: true})
    m.render(document.querySelector("#plot1"), xyplot)
}
</script>

~~~

