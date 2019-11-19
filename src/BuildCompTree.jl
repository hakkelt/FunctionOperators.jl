# ----------------------------------------------------------
# ---------------  Build computational tree  ---------------
# ----------------------------------------------------------
# -- Inner nodes are FunctionOperatorComposite objects, ----
# --------- leaves are FunctionOperator objects. -----------
# ----------------------------------------------------------

# +, -, and * operators combines the mappings on the left and right side into a
# FunctionOperatorComposite object. Assertions on type and size made when applicable.

Base.:+(FO1::FunOp, FO2::FunOp) = begin
    assertType(FO1, FO2)
    assertAddDim(FO1, FO2)
    FunctionOperatorComposite(FO1, FO2,  :+)
end

Base.:+(FO::FunOp, S::LinearAlgebra.UniformScaling) = begin
    assertAddDimScaling(FO, S)
    FunctionOperatorComposite(FO, createScalingForAddSub(FO, S),  :+)
end

Base.:+(S::LinearAlgebra.UniformScaling, FO::FunOp) = begin
    assertAddDimScaling(FO, S)
    FunctionOperatorComposite(createScalingForAddSub(FO, S), FO,  :+)
end

Base.:-(FO1::FunOp, FO2::FunOp) = begin
    assertType(FO1, FO2)
    assertAddDim(FO1, FO2)
    FunctionOperatorComposite(FO1, FO2,  :-)
end

Base.:-(FO::FunOp, S::LinearAlgebra.UniformScaling) = begin
    assertAddDimScaling(FO, S)
    FunctionOperatorComposite(FO, createScalingForAddSub(FO, S),  :-)
end

Base.:-(S::LinearAlgebra.UniformScaling, FO::FunOp) =  begin
    assertAddDimScaling(FO, S)
    FunctionOperatorComposite(createScalingForAddSub(FO, S), FO,  :-)
end

Base.:*(FO1::FunOp, FO2::FunOp) = begin
    assertType(FO1,FO2)
    assertMultDim(FO1, FO2)
    FunctionOperatorComposite(FO1, FO2,  :*)
end

Base.:*(FO::FunctionOperator, S::LinearAlgebra.UniformScaling{Bool}) =
    FunctionOperator(FO, name = getName(FO) * " * I")

Base.:*(FO::FunctionOperatorComposite, S::LinearAlgebra.UniformScaling{Bool}) =
    FunctionOperatorComposite(FO, name = getName(FO) * " * I")

Base.:*(S::LinearAlgebra.UniformScaling{Bool}, FO::FunctionOperator) = 
    FunctionOperator(FO, name = "I * " * getName(FO))

Base.:*(S::LinearAlgebra.UniformScaling{Bool}, FO::FunctionOperatorComposite) = 
    FunctionOperatorComposite(FO, name = "I * " * getName(FO))

Base.:*(FO::FunOp, S::LinearAlgebra.UniformScaling) =
    FunctionOperatorComposite(FO, createScalingForMult(FO, S, FO.inDims),  :*)

Base.:*(S::LinearAlgebra.UniformScaling, FO::FunOp) =
    FunctionOperatorComposite(createScalingForMult(FO, S, FO.outDims), FO,  :*)

Base.:*(FO::FunOp, λ::Number) = FO * (λ*I)

Base.:*(λ::Number, FO::FunOp) = (λ*I) * FO

# Adjoint operator creates a new FunctionOperatorComposite object, toggles the adjoint field and
# switches the input and output dimension constraints (and also voids plan for FunctionOperatorComposite)

Base.:adjoint(FO::FunctionOperator) =
    FunctionOperator(FO, adjoint = !FO.adjoint, inDims = FO.outDims, outDims = FO.inDims)

Base.:adjoint(FO::FunctionOperatorComposite{T}) where {T} = begin
    FunctionOperatorComposite(FO, name = "("*getName(FO)*")'", adjoint = !FO.adjoint,
        inDims = FO.outDims, outDims = FO.inDims, plan_function = noplan)
end