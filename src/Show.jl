# ----------------------------------------------------------
# ------------------------  Show  --------------------------
# ----------------------------------------------------------
# I think it is pretty much self-explenatory

Base.show(io::IO, FO::FunctionOperator) =
    print(io, "FunctionOperator{$(FO.datatype), $(FO.name), $(FO.inDims), $(FO.outDims)}")

Base.show(io::IO, ::MIME"text/plain", FO::FunctionOperator) =
    print(io, """
FunctionOperator
    Data type: $(FO.datatype)
    Name: $(FO.name)
    Input dimensions: $(FO.inDims)
    Output dimensions: $(FO.outDims)""")

Base.show(io::IO, FO::FunctionOperatorComposite) =
    print(io, "FunctionOperatorComposite{$(FO.datatype), $(FO.name), $(FO.inDims), $(FO.outDims), $(FO.plan_string)}")

Base.show(io::IO, ::MIME"text/plain", FO::FunctionOperatorComposite) =
    print(io, """
FunctionOperatorComposite
    Data type: $(FO.datatype)
    Name: $(FO.name)
    Input dimensions: $(FO.inDims)
    Output dimensions: $(FO.outDims)
    Plan: $(FO.plan_string)""")