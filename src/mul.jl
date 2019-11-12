# ----------------------------------------------------------
# ---------------  Apply operator to arrays  ---------------
# ----------------------------------------------------------

# In case of applying a single FunctionOperator to the data, everything is quite straightforward:
# We make sure that operator and the data (and maybe the buffer) works together, and then apply
# the forw or backw field of FunctionOperator based on the value of adjoint field.

Base.:*(FO::FunctionOperator, A::AbstractArray) = begin
    assertType(FO, A)
    assertMultDim(FO, A)
    info("Allocation of buffer1, size: $(FO.outDims)")
    FO.adjoint ?
        FO.mutating ? FO.backw(Array{FO.datatype}(undef, FO.outDims), A) : FO.backw(A) :
        FO.mutating ? FO.forw(Array{FO.datatype}(undef, FO.outDims), A) : FO.forw(A)
end

LinearAlgebra.mul!(buffer::AbstractArray, FO::FunctionOperator, A::AbstractArray) = begin
    assertType(FO, A)
    assertTypeBuffer(FO, buffer)
    assertMultDim(FO, A)
    assertMultDimBuffer(FO, buffer)
    FO.adjoint ?
        (FO.mutating ? FO.backw(buffer, A) : buffer .= FO.backw(A)) :
        (FO.mutating ? FO.forw(buffer, A) : buffer .= FO.forw(A))
end

# When FunctionOperatorComposite is applied to data, the process changes only slightly:
# After checking if plan is already calculated (if not, then we allocate the buffer, and then calculate the plan), then we can apply the aggrataged function to the data.

Base.:*(FO::FunctionOperatorComposite, A::AbstractArray) = begin
    assertType(FO, A)
    assertMultDim(FO, A)
    storage = Array{Buffer,1}(undef, 0)
    buffer1 = newBuffer(FO.datatype, FO.outDims, storage)
    if FO.plan_function == noplan
        FO.plan_function, output, FO.plan_string = getPlan(FO, buffer1, FO.adjoint, "x", storage)
        info("Plan calculated: $(output.name) .= "*FO.plan_string)
        @assert output.name == "buffer1" "Implementation error: Output of computation is written to $(output.name) instead of buffer1"
    end
    FO.plan_function(buffer1.buffer, A)
end

LinearAlgebra.mul!(buffer::AbstractArray, FO::FunctionOperatorComposite, A::AbstractArray) = begin
    assertType(FO, A)
    assertType(FO, buffer)
    assertMultDim(FO, A)
    assertMultDimBuffer(FO, buffer)
    if FO.plan_function == noplan
        storage = Array{Buffer}(undef, 0)
        buffer1 = Buffer(buffer, "buffer1", 1, true)
        push!(storage, buffer1)
        info("buffer1 = <previously allocated>")
        FO.plan_function, output, FO.plan_string = getPlan(FO, buffer1, FO.adjoint, "x", storage)
        info(("Plan calculated: $(output.name) .= "*FO.plan_string))
        @assert output.buffer == buffer "Implementation error: Output of computation is written to $(output.name) instead of buffer1"
    end
    FO.plan_function(buffer, A)
end