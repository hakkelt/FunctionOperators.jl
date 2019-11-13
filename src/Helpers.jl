# ----------------------------------------------------------
# ------------------  Helper functions  --------------------
# ----------------------------------------------------------

# Used to print memory allocations and the calculated plan
# Prints nothing if FO_settings.verbose == false
info(str::String) =
    FO_settings.verbose && println(str)

"Determine type of elements of array accepted by this operator"
Base.eltype(::Type{FunctionOperator{T}}) where {T} = T
Base.eltype(::Type{FunctionOperatorComposite{T}}) where {T} = T

# ---------------------  Assertions  -----------------------

# Enforce equality of types of operators to be combined,
# or equality of type of array and the operator to be applied on it
assertType(left, right) =
    eltype(left) != eltype(right) && (isa(right, AbstractArray) ?
        throw(TypeError(:*, "{$(left.name)} * {array}", eltype(left), eltype(right))) :
        throw(TypeError(:*, "{$(left.name)} * {$(right.name))}", eltype(left), eltype(right))))

# Used by mul!
# Check if the type of array given as buffer for output matches the type of the operator
assertTypeBuffer(left, right) =
    eltype(left) != eltype(right) &&
        throw(TypeError(:mul!, "output buffer type check", eltype(right), eltype(left)))

# Check size compatibility of left and right side of multiplication
# Left side is always a subtype of FunOp, but the right side can be either FunOp or AbstractArray
assertMultDim(left, right) = 
    isa(right, AbstractArray) ?
        left.inDims != size(right) &&
            throw(DimensionMismatch("{$(left.name)} is size of $(left.inDims) and the given array is size of $(size(right))")) :
        left.inDims != right.outDims &&
            throw(DimensionMismatch("{$(left.name)} is size of $(left.inDims) and {$(right.name)} is size of $(right.outDims)"))

# Used by mul!
# Check if the size of array given as buffer for output matches the type of the operator
assertMultDimBuffer(left, right) =
    left.outDims != size(right) &&
        throw(DimensionMismatch("Size of result of the multiplication ($(left.inDims)) doesn't  match the size of the first argument $(size(right))"))

# Check size compatibility of left and right side of addition or substraction
# Left side is always a subtype of FunOp, but the right side can be either FunOp or AbstractArray
assertAddDim(left, right) = begin
    left.inDims != right.inDims &&
        throw(DimensionMismatch("Input dimension of {$(left.name)} is $(left.inDims), but the input dimension of {$(right.name)} is $(right.inDims)"))
    left.outDims != right.outDims &&
        throw(DimensionMismatch("Output dimension of {$(left.name)} is $(left.outDims), but the output dimension of {$(right.name)} is $(right.outDims)"))
end

# Check size compatibility of left and right side of addition or substraction
# left is always FunOp, right is always UniformScaling
assertAddDimScaling(left, right) = begin
    left.inDims != left.outDims &&
        throw(DimensionMismatch("{$(left.name)} has input size of $(left.inDims), and its output size is $(left.ouDims). {$(right.name)} should match the input and output size of {$(left.name)}, but scaling can't change the size of its output."))
end

# ----------------  Wrap UniformScaling  -------------------

# Give string representation of UniformScaling and put parentheses around
# If λ is a complex, then put parantheses around the complex number, as well.
scalingName(scaling) =
    isa(scaling.λ, Complex) ? "(($(scaling.λ))*I)" : "("*string(scaling.λ)*"*I)"

# Create a FunctionOperator that does the scaling, and enforces input/output size that matches
# the required size of surrounding operators (which are connected by multiplication)
createScalingForMult(FO::FunOp, S::LinearAlgebra.UniformScaling, size::Tuple{Vararg{Int}}) = begin
    λ = convert(eltype(FO), S.λ)
    FunctionOperator{eltype(FO)}(name = scalingName(S),
        forw =  (buffer, x) -> buffer .= x .* λ,
        backw = (buffer, x) -> buffer .= x .* conj(λ),
        scaling = true, getScale = () -> λ, mutating = true,
        inDims = size, outDims = size)
end

# Create a FunctionOperator that does the scaling, and enforces output size that matches
# the required size of surrounding operators (which are connected by addition)
# Proper input size can only be checked when the forw/backw closure is executed
createScalingForAddSub(FO::FunOp, S::LinearAlgebra.UniformScaling) = begin
    name = scalingName(S)
    λ = convert(eltype(FO), S.λ)
    FunctionOperator{eltype(FO)}(name = name,
        forw =  (buffer, x) -> broadcast!(*, buffer, x, λ),
        backw = (buffer, x) -> broadcast!(*, buffer, x, conj(λ)),
        scaling = true, getScale = () -> λ, mutating = true,
        inDims = FO.outDims, outDims = FO.outDims)
end