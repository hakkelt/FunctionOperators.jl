module FunctionOperators
using Parameters, MacroTools, Printf, LinearAlgebra
import Base: show, *, +, -, adjoint, ==, eltype, reshape

export FunctionOperator, FunOp, reshape, setPlan, @♻, @recycle, FunctionOperators_global_settings

# Structure to hold global settings
mutable struct Settings
    verbose::Bool
    macro_verbose::Bool
    auto_reshape::Bool
end
"""
Object that holds global settings for `FunctionOperators` library

Fields:
 - `verbose::Bool` If set to true, then allocation information and calculated plan function will be displayed upon creation (i.e., when a composite operator is first used). Default: `false`
 - `macro_verbose::Bool` If set to true, then recycling macros (@♻ and @recycle) will print the transformed code. Default: `false`
 - `auto_reshape::Bool` If set to true, then input and output is reshaped according to the inDims and outDims values of the FunctionOperator before and after any multiplication. Default: `false`
"""
const FunctionOperators_global_settings = Settings(false, false, false)

include("StructDefs.jl")
include("Helpers.jl")
include("Show.jl")
include("BuildCompTree.jl")
include("getPlan.jl")
include("mul.jl")
include("Auxiliary.jl")
include("recycle.jl")

end # module