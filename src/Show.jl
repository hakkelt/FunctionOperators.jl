# ----------------------------------------------------------
# ------------------------  Show  --------------------------
# ----------------------------------------------------------
# I think it is pretty much self-explenatory

Base.show(io::IO, FO::FunctionOperator) =
    print(io, "FunctionOperator{$(eltype(FO))}($(FO.name), $(FO.inDims), $(FO.outDims))")

Base.show(io::IO, ::MIME"text/plain", FO::FunctionOperator) =
    print(io, """
FunctionOperator with eltype $(eltype(FO))
    Name: $(FO.name)
    Input dimensions: $(FO.inDims)
    Output dimensions: $(FO.outDims)""")

Base.show(io::IO, FO::FunctionOperatorComposite) =
    print(io, "FunctionOperatorComposite{$(eltype(FO))}($(FO.name), $(FO.inDims), $(FO.outDims), $(FO.plan_string))")

Base.show(io::IO, ::MIME"text/plain", FO::FunctionOperatorComposite) =
    print(io, """
FunctionOperatorComposite with eltype $(eltype(FO))
    Name: $(FO.name)
    Input dimensions: $(FO.inDims)
    Output dimensions: $(FO.outDims)
    Plan: $(FO.plan_string)""")