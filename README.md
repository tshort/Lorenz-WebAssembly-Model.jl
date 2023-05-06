
## 

The app and instructions are at [Lorenz Attraction App in Julia](http://tshort.github.io/Lorenz-WebAssembly-Model.jl). 

Of the files in this folder, the main ones that are special to this app are:

* `index.md` - Compiles the WebAssembly and defines the user interface for the app.
* `utils.jl` - Defines a custom Franklin function.
* `walloc.*` - Memory allocation.
* `/_libs/mdpad/*` - UI package.
* `/_libs/wasm-ffi.browser.js` - WebAssembly interface package.

The rest of the files are set up for the PkgPage template or the Julia package environment.
