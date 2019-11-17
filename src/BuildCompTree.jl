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

Base.:+(FO1::FunOp, S::LinearAlgebra.UniformScaling) = begin
    assertAddDimScaling(FO1, S)
    FunctionOperatorComposite(FO1, createScalingForAddSub(FO1, S),  :+)
end

Base.:+(S::LinearAlgebra.UniformScaling, FO2::FunOp) = begin
    assertAddDimScaling(FO2, S)
    FunctionOperatorComposite(createScalingForAddSub(FO2, S), FO2,  :+)
end

Base.:-(FO1::FunOp, FO2::FunOp) = begin
    assertType(FO1, FO2)
    assertAddDim(FO1, FO2)
    FunctionOperatorComposite(FO1, FO2,  :-)
end

Base.:-(FO1::FunOp, S::LinearAlgebra.UniformScaling) = begin
    assertAddDimScaling(FO1, S)
    FunctionOperatorComposite(FO1, createScalingForAddSub(FO1, S),  :-)
end

Base.:-(S::LinearAlgebra.UniformScaling, FO2::FunOp) =  begin
    assertAddDimScaling(FO2, S)
    FunctionOperatorComposite(createScalingForAddSub(FO2, S), FO2,  :-)
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

Base.:*(FO1::FunOp, S::LinearAlgebra.UniformScaling) =
    FunctionOperatorComposite(FO1, createScalingForMult(FO1, S, FO1.inDims),  :*)

Base.:*(S::LinearAlgebra.UniformScaling{Bool}, FO::FunctionOperator) = 
    FunctionOperator(FO, name = "I * " * getName(FO))

Base.:*(S::LinearAlgebra.UniformScaling{Bool}, FO::FunctionOperatorComposite) = 
    FunctionOperatorComposite(FO, name = "I * " * getName(FO))

Base.:*(S::LinearAlgebra.UniformScaling, FO2::FunOp) =
    FunctionOperatorComposite(createScalingForMult(FO2, S, FO2.outDims), FO2,  :*)

# Adjoint operator creates a new FunctionOperatorComposite object, toggles the adjoint field and
# switches the input and output dimension constraints (and also voids plan for FunctionOperatorComposite)

Base.:adjoint(FO::FunctionOperator) =
    FunctionOperator(FO, adjoint = !FO.adjoint, inDims = FO.outDims, outDims = FO.inDims)

Base.:adjoint(FO::FunctionOperatorComposite{T}) where {T} = begin
    FunctionOperatorComposite(FO, name = "("*getName(FO)*")'", adjoint = !FO.adjoint,
        inDims = FO.outDims, outDims = FO.inDims, plan_function = noplan)
end