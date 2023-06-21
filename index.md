\begin{section}{}
~~~<div id="mdpad"></div></div>
~~~
\end{section}

\begin{section}{title="Components"}

This is an example app to demonstrate how Julia code for DiffEq-type simulations can be compiled for use on the web. This app is built with the following:

* [StaticCompiler](https://github.com/tshort/StaticCompiler.jl) compiles a Julia model to WebAssembly. This uses [GPUCompiler](https://github.com/JuliaGPU/GPUCompiler.jl) which does most of the work. [StaticTools](https://github.com/brenhinkeller/StaticTools.jl) helps with this static compilation.
* [DiffEqGPU](https://github.com/SciML/DiffEqGPU.jl) provides simulation code that is amenable to static compilation.
* [WebAssemblyInterfaces](https://github.com/tshort/WebAssemblyInterfaces.jl) and [wasm-ffi](https://github.com/demille/wasm-ffi) provide convenient ways to interface between JavaScript and Julia/WebAssembly code.
* [mdpad](https://mdpad.netlify.app/) provides features for single-page web apps.
* [PkgPage](https://github.com/tlienart/PkgPage.jl) and [Franklin](https://github.com/tlienart/Franklin.jl) build this page from Markdown. The source code on this page also compiles the WebAssembly modeling code.

\end{section}

\begin{section}{title="WebAssembly"}

Here is the model with initial conditions that we'll compile. The important part is using [DiffEqGPU](https://github.com/SciML/DiffEqGPU.jl) to set up an integrator. Because it is designed to run on a GPU, it is natural for static compilation. It doesn't allocate or use features from `libjulia`.

```julia:j1
# Tested with DiffEqGPU v2.3.1
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

integ = DiffEqGPU.init(GPUTsit5(), prob.f, false, u0, 0.0, 0.005, p, nothing, CallbackSet(nothing), true, false)
```

Now, we can define a function to solve this model. We won't use `DiffEqGPU.solve()` because that's too complicated. Instead, we'll use `integ` and manually step through the solution. We'll update solution vectors along the way. 

```julia:j2
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
```

Now, we can compile `solv` to the WebAssembly file `_libs/julia_solv.wasm` using `StaticCompiler.compile_wasm`. `StaticTools.MallocVector` is used for the solution vectors. When compiling, `flags` are passed to the WebAssembly linker (`lld -flavor wasm`), and we can include the initial memory size and other files to link in. Initial memory must be big enough to hold objects we'll use.

```julia:j3
using StaticCompiler, StaticTools

compile_wasm(solv, 
    Tuple{typeof(integ), 
          MallocVector{Float64}, MallocVector{Float64}, 
          MallocVector{Float64}, MallocVector{Float64}}, 
    path = "_libs",
    flags = `--initial-memory=1048576 walloc.o`, filename = "julia_solv")
```

[StaticCompiler](https://github.com/tshort/StaticCompiler.jl) can only compile a restricted subset of Julia code. [DiffEqGPU](https://github.com/SciML/DiffEqGPU.jl) is amenable to static compilation. It doesn't have internal allocations or use of Arrays or other code needing `libjulia` functionality. Note that DiffEqGPU has fewer options for solvers, and solvers are not as robust as standard DiffEq packages.  

Note that WebAssembly in browsers is mainly a 32-bit system (`wasm32`). A 64-bit Julia can compile to `wasm32`, but the best approach is to use a 32-bit version of Julia, so the memory layouts are closer. This page was developed locally with 64-bit Julia.

\end{section}

\begin{section}{title="Interfacing"}


[wasm-ffi](https://github.com/demille/wasm-ffi) is a great JavaScript package that provides convenient ways to interface between JavaScript and WebAssembly code. It can allocate objects in WebAssembly memory and provides conveniences to read and write to those objects. We use the Julia package [WebAssemblyInterfaces](https://github.com/tshort/WebAssemblyInterfaces.jl) to generate JavaScript code for `wasm-ffi`. 

WebAssembly has no automatic memory management. All WebAssembly memory must be manually allocated and freed. `wasm-ffi` will allocate objects upon definition. The WebAssembly code must include `allocate` and `deallocate` functions. Up above, we linked to the file `walloc.o` in the `--initial-memory=1048576 walloc.o` statement. This is from [walloc](https://github.com/wingo/walloc). The `flags` argument is passed to the linker and can include other `wasm32` object files. The memory must be a multiple of 65536 bytes.

[This](https://github.com/SciML/DiffEqGPU.jl/blob/73f76809439424245d7bfd48f70c9a625e29101c/src/integrators/types.jl#L11-L46) is the definition of the integrator used by `solv`. It is a mutable struct. Here is how we generate interfacing code that generates types in JavaScript that will replicate the memory layout we need in Julia:

```julia:j4
using WebAssemblyInterfaces

integ_types = js_types(typeof(integ))
integ_def = js_def(integ)

println(integ_types)
```
\output{j4}

We will later use both of these results to splice this into our JavaScript code included in this file. 

On the JavaScript side, we can manipulate the object as you would expect, like `integ.dt = 0.2` or `integ.p = [12, 3, 4]`.

\end{section}

\begin{section}{title="Publishing"}

WebAssembly files can be used in any type of web page, including those created with static-site generators like Jekyll. Julia has several great options for creating HTML pages, including [Documenter](https://documenter.juliadocs.org/stable/), [Franklin](https://franklinjl.org/), and [Literate](https://fredrikekre.github.io/Literate.jl/v2/). For this page, I used [PkgPage](https://tlienart.github.io/PkgPage.jl/) which is nice for "one pagers". Using a Julia-based option is nicer in that we can use the results and stuff them in the page. For example, the interfacing code above is directly included with a custom PkgPage/Franklin HTML command.

We also need JavaScript to control interactivity. (Doing this on the Julia/WebAssembly side is not yet feasible.) There are so many JavaScript packages, it's hard to pick. Here, I use [mdpad](https://mdpad.netlify.app/) which has features that are nice for one-page apps. To use it, we need to define `mdpad_init` and `mdpad_update` functions. I used [Mithril.js](https://mithril.js.org/) to generate inputs and outputs. 

To start with, we'll write out our interfacing code from above. We'll use a custom Franklin HTML command to insert this into the HTML for this page (`{{ rawoutput j5 }}` later in this file). `integ_types` is just stored as regular definition. `integ_def` is defined as a function to allow new instances to be created.

```julia:j5
println("<script>\n", integ_types, "\n\n")
println("function new_integ() {return ", integ_def, "\n}\n</script>")
```

Now, we need to define our interfacing code using wasm-ffi. This code is included in this Markdown file with `~~~` delimeters. `ffi.rust.vector` maps to a `StaticTools.MallocVector`.

```c
const library = new ffi.Wrapper({
  julia_solv: ['number', [GPUTsit5Integrator, ffi.rust.vector('f64'), ffi.rust.vector('f64'),
                                              ffi.rust.vector('f64'), ffi.rust.vector('f64')]],
}, {debug: false});

library.imports(wrap => ({
  env: {
    memory: new WebAssembly.Memory({ initial: 16 }),
  },
}));
```
Here are definitions for output vectors passed to Julia code.

```c
var t = new ffi.rust.vector('f64', new Float64Array(10000))
var u1 = new ffi.rust.vector('f64', new Float64Array(10000))
var u2 = new ffi.rust.vector('f64', new Float64Array(10000))
var u3 = new ffi.rust.vector('f64', new Float64Array(10000))
```

In `mdpad_init`, we load the WebAssembly file `libs/julia_solv.wasm` and then create an input form.

```c
async function mdpad_init() {
    await library.fetch('libs/julia_solv.wasm')
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
}
```

`mdpad_update`, creates allocates a new integrator, updates the initial conditions using data from the form, and runs `julia_solv`. `julia_solv` fills up the output vectors, and we plot these with Plotly.
 
```c
function mdpad_update() {
    var integ = new_integ();
    integ.p.data = [mdpad.p1, mdpad.p2, mdpad.p3];
    library.julia_solv(integ, t, u1, u2, u3);
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
```

That's it! Overall, the experience with PkgPage is rather interactive. During development, make changes to the Julia code, the Markdown, or the JavaScript code, save the file, and watch results update in the browser.

This work takes inspiration from this cool [fluid simulation tool](https://github.com/Alexander-Barth/FluidSimDemo-WebAssembly) in Julia/WebAssembly by Alexander Barth.

\end{section}










~~~

<script src="libs/mdpad/mdpad.js"></script>
<script src="libs/mdpad/mdpad-mithril.js"></script>
<script src="libs/wasm-ffi.browser.js"></script>

~~~
{{ rawoutput j5 }}
~~~

<script src="https://cdnjs.cloudflare.com/ajax/libs/mithril/2.0.4/mithril.min.js"></script>
<script src="https://cdn.plot.ly/plotly-basic-1.54.1.min.js"></script>


<script>
const library = new ffi.Wrapper({
  julia_solv: ['number', [GPUTsit5Integrator, ffi.rust.vector('f64'), ffi.rust.vector('f64'),
                                              ffi.rust.vector('f64'), ffi.rust.vector('f64')]],
}, {debug: false});

library.imports(wrap => ({
  env: {
    memory: new WebAssembly.Memory({ initial: 16 }),
  },
}));

var t = new ffi.rust.vector('f64', new Float64Array(10000))
var u1 = new ffi.rust.vector('f64', new Float64Array(10000))
var u2 = new ffi.rust.vector('f64', new Float64Array(10000))
var u3 = new ffi.rust.vector('f64', new Float64Array(10000))


async function mdpad_init() {
    await library.fetch('libs/julia_solv.wasm')
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
}

function mdpad_update() {
    var integ = new_integ();
    integ.p.data = [mdpad.p1, mdpad.p2, mdpad.p3];
    library.julia_solv(integ, t, u1, u2, u3);
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

