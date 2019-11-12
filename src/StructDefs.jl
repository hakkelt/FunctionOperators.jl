# ----------------------------------------------------------
# ---------  Struct definitions and constructors  ----------
# ----------------------------------------------------------

# Default value of the FunctionOperatorComposite's plan field
# This variable is also used to check if FunctionOperatorComposite's plan field has the default value
noplan = () -> ()

"""
Supertype for FunctionOperator and FunctionOperatorComposite
"""
abstract type FunOp end

# Returns the number of arguments
nargs(f::Function) = first(methods(f)).nargs
# forw and backw functions are called mutating if they have two arguments;
# thus, they mutate the buffer given as first argument
checkMutating(f::Function) = (nargs(f) == 3)

# @with_kw_noshow from Parameters.jl generates keyword arg. constructor with default values
# and also a copy constructor which can accept keywords args that overwrites values copied
# from the other instant
"""
Constructor for FunctionOperator object

FunctionOperator is an operator that maps from a multidimensional space to another multidimensional space. The mapping is defined by a function (`forw`), and optionally the reverse mapping can also be defined (`backw`). The input the mapping must be subtype of AbstractArray.

Arguments
 - `datatype::Type` Type that is enforced on elements of input array
 - `name::String` The operator is referenced later in error messages by this string. **Warning!** It is also used to check equality of (composite) FunctionOperators.
 - `forw::Function` Function defining the mapping. Must accept one or two arguments. In case of two arguments, the first argument is a preallocated buffer to write the result into (to speed up code by avoiding repeated allocations). In case of both one and two arguments, the return value must be the result of the mapping.
 - `backw::Function` (Optional) Same as backw, but defines the backward mapping
 - `inDims::Tuple{Vararg{Int}}` Size of input array
 - `outDims::Tuple{Vararg{Int}}` Size of output array

The following constructors are available:
 - Positional constructor #1: `FunctionOperator(datatype, name, forw, inDims, outDims)`
 - Positional constructor #2: `FunctionOperator(datatype, name, forw, backw inDims, outDims)`
 - Keyword constructor #1: `FunctionOperator(;kwargs...)` -> Note that only `backw` is optional!
"""
@with_kw_noshow struct FunctionOperator <: FunOp
    datatype::Type
    name::String
    forw::Function
    backw::Function = () -> error("backward function not implemented for "*name)
    adjoint::Bool = false # op' creates a new FunctionOperator that is similar to op, but this field is negated
    mutating::Bool = checkMutating(forw) # true if forw has two arguments
    scaling::Bool = false # true if the FunctionOperator is created from LinearAlgebra.UniformScaling object
    getScale::Function = () -> () # This is used only if this FunctionOperator is a scaling
    inDims::Tuple{Vararg{Int}}
    outDims::Tuple{Vararg{Int}}
        # Some assertions placed in the 
        @assert (2 <= nargs(forw) <= 3)  "forw can only accept either one or two inputs"
        @assert (2 <= nargs(backw) <= 3) "backw can only accept either one or two inputs"
        @assert (nargs(forw) == nargs(backw)) "forw and backw must accept the same number of inputs!"
end

# Constructor with positional arguments, skipping fields with default values
FunctionOperator(datatype::Type, name::String, forw::Function,
        inDims::Tuple{Vararg{Int}}, outDims::Tuple{Vararg{Int}}) =
    FunctionOperator(datatype=datatype, name=name, forw=forw, inDims=inDims, outDims=outDims)

# Constructor with positional arguments, but skipping fields with default values
FunctionOperator(datatype::Type, name::String, forw::Function, backw::Function,
        inDims::Tuple{Vararg{Int}}, outDims::Tuple{Vararg{Int}}) =
    FunctionOperator(datatype=datatype, name=name, forw=forw, backw=backw, inDims=inDims, outDims=outDims)

# Structure holding a combination of FunctionOperators
# It is mutable because plan, plan_string and plan_buffer fields are changed
# after applying the operator to an array
@with_kw_noshow mutable struct FunctionOperatorComposite <: FunOp
    datatype::Type
    name::String
    left::FunOp
    right::FunOp
    operator::Symbol
    adjoint::Bool = false
    mutating::Bool
    inDims::Tuple{Vararg{Int}}
    outDims::Tuple{Vararg{Int}}
    plan_function::Function = noplan
    plan_string::String = "no plan"
end

# Get the value of the name field and append ' if it is adjoint
getName(FO::FunctionOperator) = FO.adjoint ? FO.name*"'" : FO.name
getName(FO::FunctionOperatorComposite) = FO.adjoint ? "($(FO.name))'" : FO.name

# Constructor that combines two FunOp objects
function FunctionOperatorComposite(FO1::FunOp, FO2::FunOp, op::Symbol)
    name = getName(FO1) * " $op " * getName(FO2)
    name = op == :* ? name : "($name)"
    FunctionOperatorComposite(
        datatype = FO1.datatype,
        name = name,
        left = FO1,
        right = FO2,
        operator = op,
        mutating = (FO1.mutating || FO2.mutating),
        inDims = FO2.inDims,
        outDims = FO1.outDims)
end