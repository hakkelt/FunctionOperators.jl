# FunctionOperators.jl

[![](https://img.shields.io/badge/docs-latest-blue.svg)](https://hakkelt.github.io/FunctionOperators.jl/latest/)
[![Build Status](https://travis-ci.com/hakkelt/FunctionOperators.jl.svg?branch=master)](https://travis-ci.com/hakkelt/FunctionOperators.jl)
[![codecov](https://codecov.io/gh/hakkelt/FunctionOperators.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/hakkelt/FunctionOperators.jl)

## Motivation

I wanted to write code for image reconstruction in Julia, which

- resambles the mathematical notation with abstract operators on multidimensional spaces,
- has minimal memory requirement and fast to run, and
- is easy to write and read.

FunctionOperator is an operator that maps from a multidimensional space to another multidimensional space. The mapping is defined by a function (`forw`), and optionally the reverse mapping can also be defined (`backw`). The input the mapping must be subtype of AbstractArray.

## Examples

### Create operator

The 2D Fourier transformation operator:

```julia
julia> using FFTW
julia> 𝓕 = FunctionOperator{Complex{Float64}}(
            forw = x -> fft(x, (1,2)), backw = x -> ifft(x, (1,2)),
            inDims = (128, 128), outDims = (128, 128))
```

Finite differences / Total Variance operator:

```julia
julia> ∇ = FunctionOperator{Complex{Float64}}(
            forw = x -> (circ(x, (1,0)) - x).^2 + (circ(x, (0,1)) - x).^2,
            inDims = (128, 128), outDims = (128, 128))
```

Or a sampling operator:

```julia
julia> mask = rand(128, 128) .< 0.3
julia> S = FunctionOperator{Complex{Float64}}(
            forw = x -> x[mask], backw = x -> embed(x, mask),
            inDims = (128, 128), outDims = (sum(mask),))
```

Then these operators can be combined (almost) arbitrarily:

```julia
julia> x = rand(128, 128);
julia> 𝓕 * ∇ * x == fft((circ(x, (1,0)) - x).^2 + (circ(x, (0,1)) - x).^2, (1,2))
true
julia> combined = S * (𝓕 + ∇);
julia> combined * x == S * 𝓕 * x + S * ∇ * x
true
```

They can be combined with `UniformScaling` from `LinearAlgebra`:

```julia
julia> using LinearAlgebra
julia> 3I * ∇ * x == 3 * (∇ * x)
true
julia> (𝓕 + (3+2im)I) * x == 𝓕 * x + (3+2im) * x
true
```

### Performance

With little effort we can achieve the same speed as we would have manually optimized functions. For example, consider the following function:

```julia
julia> using BenchmarkTools
julia> FFT_plan = plan_fft(x, (1,2));
julia> iFFT_plan = plan_ifft!(x, (1,2));
julia> function foo(output::Array{Complex{Float64},2}, x::Array{Complex{Float64},2},
                FFT_plan, iFFT_plan, mask::BitArray)
            mul!(output, FFT_plan, x)
            output .*= mask
            mul!(output, iFFT_plan, output)
        end;
julia> output = similar(x);
julia> @benchmark foo(output, x, FFT_plan, iFFT_plan, mask)
BenchmarkTools.Trial:
  memory estimate:  0 bytes
  allocs estimate:  0
  --------------
  minimum time:     390.961 μs (0.00% GC)
  median time:      418.149 μs (0.00% GC)
  mean time:        408.111 μs (0.00% GC)
  maximum time:     497.468 μs (0.00% GC)
  --------------
  samples:          10000
  evals/sample:     1
```

That function basically consist of three operations: A Fourier transform, a masking, and an inverse Fourier transform. Using FunctionOperators, we can write code that is more similar to the high-level description that has minimal run-time and memory overhead:

```julia
julia> 𝓕₂ = FunctionOperator{Complex{Float64}}(
            forw = (output, x) -> mul!(output, FFT_plan, x),
            backw = (output, x) -> mul!(output, iFFT_plan, x),
            inDims = (128, 128), outDims = (128, 128));
julia> S₂ = FunctionOperator{Complex{Float64}}(
            forw = (output, x) -> output .= x .* mask,
            inDims = (128, 128), outDims = (128, 128));
julia> combined = 𝓕₂' * S₂ * 𝓕₂;
julia> @benchmark mul!(output, combined, x)
BenchmarkTools.Trial:
  memory estimate:  112 bytes
  allocs estimate:  4
  --------------
  minimum time:     401.814 μs (0.00% GC)
  median time:      429.648 μs (0.00% GC)
  mean time:        427.211 μs (0.00% GC)
  maximum time:     681.116 μs (0.00% GC)
  --------------
  samples:          10000
  evals/sample:     1
```
  
For more detailed description, see [tutorial](https://hakkelt.github.io/FunctionOperators.jl/latest/Tutorial/).

## Related packages

Not a Julia package, but the main motivation behind creating this package is to have the same functionality as `fatrix2` in the Matlab version of [Michigan Image Reconstruction Toolbox (MIRT)](https://github.com/JeffFessler/mirt), ([description](https://web.eecs.umich.edu/~fessler/irt/irt/doc/doc.pdf)).

The most similar Julia package is [AbstractOperators.jl](https://github.com/kul-forbes/AbstractOperators.jl). The feature set of its `MyLinOp` type largely overlaps with `FunctionOperator`'s features. The main difference is that composition in `AbstractOperators` is more intensive memory-wise as it allocates a buffer for each member of composition while `FunctionOperators` allocates a new buffer only when necessary. On the other hand, the difference between is significant only for memory-intensive applications.

`FunctionOperators` was also inspired by [LinearMaps.jl](https://github.com/Jutho/LinearMaps.jl)  The main difference is that `LinearMaps` support only mappings where the input and output are both vectors (which is often not the case in image reconstruction algorithms). [LinearMapsAA.jl](https://github.com/JeffFessler/LinearMapsAA.jl) is an extension of [LinearMaps.jl](https://github.com/Jutho/LinearMaps.jl) with `getindex` and `setindex!` functions making it conform to the requirements of an AbstractMatrix type. Additionally, a user can include a NamedTuple of properties with it, and then retrieve those later using the `A.key` syntax like one would do with a struct (composite type). From implementational point of view, both [LinearMaps.jl](https://github.com/Jutho/LinearMaps.jl) and [LinearMapsAA.jl](https://github.com/JeffFessler/LinearMapsAA.jl) uses more memory when `LinearMaps` with different input and output size are composed.

[LinearOperators](https://github.com/JuliaSmoothOptimizers/LinearOperators.jl) provides some similar features too, but it also requires the input and the output to be a vector.
