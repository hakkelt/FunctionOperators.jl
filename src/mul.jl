# ----------------------------------------------------------
# ---------------  Apply operator to arrays  ---------------
# ----------------------------------------------------------

# In case of applying a single FunctionOperator to the data, everything is quite straightforward:
# We make sure that operator and the data (and maybe the buffer) works together, and then apply
# the forw or backw field of FunctionOperator based on the value of adjoint field.

Base.:*(FO::FunctionOperator, A::AbstractArray) = begin
    assertType(FO, A)
    FunctionOperators_global_settings.auto_reshape ? (A = reshape(A, FO.inDims)) : assertMultDim(FO, A)
    info("Allocation of buffer0, size: $(FO.outDims)")
    result = FO.adjoint ?
        FO.ismutating ? FO.backw(Array{eltype(FO)}(undef, FO.outDims), A) : FO.backw(A) :
        FO.ismutating ? FO.forw(Array{eltype(FO)}(undef, FO.outDims), A) : FO.forw(A)
    FunctionOperators_global_settings.auto_reshape ? reshape(result, FO.outDims) : result
end

LinearAlgebra.mul!(buffer::AbstractArray, FO::FunctionOperator, A::AbstractArray) = begin
    assertType(FO, A)
    assertTypeBuffer(FO, buffer)
    orig_buffer = buffer
    if FunctionOperators_global_settings.auto_reshape
        A = reshape(A, FO.inDims)
        buffer = reshape(buffer, FO.outDims)
    else
        assertMultDim(FO, A)
        assertMultDimBuffer(FO, buffer)
    end
    result = FO.adjoint ?
        (checkTwoInputs(FO.backw) ? FO.backw(buffer, A) : buffer .= FO.backw(A)) :
        (checkTwoInputs(FO.forw) ? FO.forw(buffer, A) : buffer .= FO.forw(A))
    (buffer !== result) && (buffer .= result)
    orig_buffer # buffer might have been reshaped, so we return the un-reshaped version
end

# When FunctionOperatorComposite is applied to data, the process changes only slightly:
# After checking if plan is already calculated (if not, then we allocate the buffer, and then calculate the plan), then we can apply the aggrataged function to the data.

Base.:*(FO::FunctionOperatorComposite, A::AbstractArray) = begin
    assertType(FO, A)
    FunctionOperators_global_settings.auto_reshape ? (A = reshape(A, FO.inDims)) : assertMultDim(FO, A)
    storage = Vector{Buffer}(undef, 0)
    buffer0 = Buffer(Array{eltype(FO)}(undef, FO.outDims), "buffer0", 1, true)
    push!(storage, buffer0)
    if FO.plan_function == noplan
        FO.plan_function, output, FO.plan_string = getPlan(FO, buffer0, FO.adjoint, "x", storage)
        info("Plan calculated: $(output.name) .= "*FO.plan_string)
        @assert output == buffer0 "Implementation error: Output of computation is written to $(output.name) instead of buffer1"
    end
    result = FO.plan_function(buffer0.buffer, A)
    FunctionOperators_global_settings.auto_reshape ? reshape(result, FO.outDims) : result
end

LinearAlgebra.mul!(buffer::AbstractArray, FO::FunctionOperatorComposite, A::AbstractArray) = begin
    assertType(FO, A)
    assertType(FO, buffer)
    orig_buffer = buffer
    if FunctionOperators_global_settings.auto_reshape
        A = reshape(A, FO.inDims)
        buffer = reshape(buffer, FO.outDims)
    else
        assertMultDim(FO, A)
        assertMultDimBuffer(FO, buffer)
    end
    if FO.plan_function == noplan
        storage = Array{Buffer}(undef, 0)
        buffer0 = Buffer(buffer, "buffer0", 1, true)
        push!(storage, buffer0)
        info("buffer0 = <previously allocated>")
        FO.plan_function, output, FO.plan_string = getPlan(FO, buffer0, FO.adjoint, "x", storage)
        info(("Plan calculated: $(output.name) .= "*FO.plan_string))
        @assert output.buffer === buffer "Implementation error: Output of computation is written to $(output.name) instead of buffer1"
    end
    result = FO.plan_function(buffer, A)
    (buffer !== result) && (buffer .= result)
    orig_buffer # buffer might have been reshaped, so we return the un-reshaped version
end