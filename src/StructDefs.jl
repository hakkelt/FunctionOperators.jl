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

mutable struct Counter
    num::Int64
end
counter = Counter(0)
getNextNum() = (counter.num += 1)

"""
Constructor for FunctionOperator object

FunctionOperator is an operator that maps from a multidimensional space to another multidimensional space. The mapping is defined by a function (`forw`), and optionally the reverse mapping can also be defined (`backw`). The input the mapping must be subtype of AbstractArray.

Arguments
 - `name::String` (Optional but strongly recommended) The operator is referenced later in error messages by this string. **Warning!** It is also used to check equality of (composite) FunctionOperators. Default value: `OpX` where X is a number incremented in each constructor-call.
 - `forw::Function` Function defining the mapping. Must accept one or two arguments. In case of two arguments, the first argument is a preallocated buffer to write the result into (to speed up code by avoiding repeated allocations). In case of both one and two arguments, the return value must be the result of the mapping.
 - `backw::Function` (Optional) Same as backw, but defines the backward mapping
 - `inDims::Tuple{Vararg{Int}}` Size of input array
 - `outDims::Tuple{Vararg{Int}}` Size of output array

The following constructors are available:
 - Positional constructor #1: `FunctionOperator{eltype}(forw, inDims, outDims)`
 - Positional constructor #2: `FunctionOperator{eltype}(forw, backw, inDims, outDims)`
 - Positional constructor #3: `FunctionOperator{eltype}(name, forw, inDims, outDims)`
 - Positional constructor #4: `FunctionOperator{eltype}(name, forw, backw, inDims, outDims)`
 - Keyword constructor: `FunctionOperator{eltype}(;kwargs...)`
where `eltype` is the type enforced on elements of input array.
"""
Base.@kwdef struct FunctionOperator{T <: Number} <: FunOp
    name::String = "Op$(getNextNum())"
    forw::Function
    backw::Function = () -> error("backward function not implemented for "*name)
    adjoint::Bool = false # adjoint operator creates a new object where this field is negated
    mutating::Bool = checkMutating(forw) # true if forw has two arguments
    scaling::Bool = false # true if created from LinearAlgebra.UniformScaling object
    getScale::Function = () -> () # This is used only if scaling field is true
    inDims::Tuple{Vararg{Int}}
    outDims::Tuple{Vararg{Int}}
end

macro funcAssert(func...)
    length(func) == 1 ?
        esc(quote
            @assert (2 <= nargs($(func[1])) <= 3)  "forw can only accept either one or two inputs"
        end) :
        esc(quote
            @assert (2 <= nargs($(func[1])) <= 3)  "forw can only accept either one or two inputs"
            @assert (2 <= nargs($(func[2])) <= 3) "backw can only accept either one or two inputs"
            @assert (nargs($(func[1])) == nargs($(func[2]))) "forw and backw must accept the same number of inputs!"
        end)
end

# Constructor with positional arguments without default valued fields
FunctionOperator{T}(forw::Function,
        inDims::Tuple{Vararg{Int}}, outDims::Tuple{Vararg{Int}}) where {T} = begin
    @funcAssert forw
    FunctionOperator{T}(forw = forw, inDims = inDims, outDims = outDims)
end

# Constructor with positional arguments without backw
FunctionOperator{T}(name::String, forw::Function,
        inDims::Tuple{Vararg{Int}}, outDims::Tuple{Vararg{Int}}) where {T} = begin
    @funcAssert forw
    FunctionOperator{T}(name = name, forw = forw, inDims = inDims, outDims = outDims)
end

# Constructor with positional arguments without name
FunctionOperator{T}(forw::Function, backw::Function,
        inDims::Tuple{Vararg{Int}}, outDims::Tuple{Vararg{Int}}) where {T} = begin
    @funcAssert forw backw
    FunctionOperator{T}(forw = forw, backw = backw, inDims=inDims, outDims=outDims)
end

# Constructor with positional arguments with all public fields
FunctionOperator{T}(name::String, forw::Function, backw::Function,
        inDims::Tuple{Vararg{Int}}, outDims::Tuple{Vararg{Int}}) where {T} = begin
    @funcAssert forw backw
    FunctionOperator{T}(name = name, forw = forw, backw = backw, inDims = inDims, outDims = outDims)
end

# Copy constructor with keywords to overwrite copied fields
FunctionOperator(FO::FunctionOperator; name::String = FO.name,
        forw::Function = FO.forw, backw::Function = FO.backw,
        adjoint::Bool = FO.adjoint, mutating::Bool = FO.mutating,
        scaling::Bool = FO.scaling, getScale::Function = FO.getScale,
        inDims::Tuple{Vararg{Int}} = FO.inDims, outDims::Tuple{Vararg{Int}} = FO.outDims) = begin
    @funcAssert forw backw
    FunctionOperator{eltype(FO)}(name, forw, backw, adjoint, mutating, scaling, getScale,
        inDims, outDims)
end

# Structure holding a combination of FunctionOperators
# It is mutable because plan, plan_string and plan_buffer fields are changed
# after applying the operator to an array
Base.@kwdef mutable struct FunctionOperatorComposite{T <: Number} <: FunOp
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

# Copy constructor with keywords to overwrite copied fields
FunctionOperatorComposite(FO::FunctionOperatorComposite; name::String = FO.name,
        left::FunOp = FO.left, right::FunOp = FO.right, operator::Symbol = FO.operator,
        adjoint::Bool = FO.adjoint, mutating::Bool = FO.mutating,
        inDims::Tuple{Vararg{Int}} = FO.inDims, outDims::Tuple{Vararg{Int}} = FO.outDims,
        plan_function::Function = FO.plan_function, plan_string::String = FO.plan_string) = begin
    FunctionOperatorComposite{eltype(FO)}(name, left, right, operator, adjoint, mutating,
        inDims, outDims, plan_function, plan_string)
end

# Constructor that combines two FunOp objects
function FunctionOperatorComposite(FO1::FunOp, FO2::FunOp, op::Symbol)
    name = getName(FO1) * " $op " * getName(FO2)
    name = op == :* ? name : "($name)"
    FunctionOperatorComposite{eltype(FO1)}(
        name = name,
        left = FO1,
        right = FO2,
        operator = op,
        mutating = (FO1.mutating || FO2.mutating),
        inDims = FO2.inDims,
        outDims = FO1.outDims)
end