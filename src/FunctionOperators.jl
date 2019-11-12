module FunctionOperators
using Parameters
using MacroTools
import Base: show, *, +, -, adjoint, ==
using LinearAlgebra

export FunctionOperator, FunOp, setPlan, @♻, FO_settings

# Structure to hold global settings
mutable struct Settings
    verbose::Bool
    macro_verbose::Bool
end
"""
Object that holds global settings for `FunctionOperators` library

Fields:
 - `verbose::Bool` If set to true, then allocation information and calculated plan function will be displayed upon creation (i.e., when a composite operator is first used).
 - `macro_verbose::Bool` If set to true, then recycling macro (@♻) will print the transformed loop.
"""
FO_settings = Settings(false, false)

include("StructDefs.jl")
include("Helpers.jl")
include("Show.jl")
include("BuildCompTree.jl")
include("getPlan.jl")
include("mul.jl")
include("Auxiliary.jl")

end # module