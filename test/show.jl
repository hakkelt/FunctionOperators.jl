using FunctionOperators, Test

@testset "Show.jl" begin
    Op₁ = FunctionOperator{Float64}("Op₁", x -> x .^ 3, x -> cbrt.(x), (10,10), (10,10))
    @test sprint(show, Op₁) == "FunctionOperator{Float64}(Op₁, (10, 10), (10, 10))"
    @test sprint(show, "text/plain", Op₁, context = :module=>@__MODULE__) == "FunctionOperator with eltype Float64\n    Name: Op₁\n    Input dimensions: (10, 10)\n    Output dimensions: (10, 10)"
    @test sprint(show, Op₁ * Op₁) == "FunctionOperatorComposite{Float64}(Op₁ * Op₁, (10, 10), (10, 10), no plan)"
    combined = Op₁ * Op₁
    combined * ones(10, 10)
    @test sprint(show, combined) == "FunctionOperatorComposite{Float64}(Op₁ * Op₁, (10, 10), (10, 10), Op₁.forw(Op₁.forw(x)))"
    @test sprint(show, "text/plain", Op₁ * Op₁, context = :module=>@__MODULE__) == "FunctionOperatorComposite with eltype Float64\n    Name: Op₁ * Op₁\n    Input dimensions: (10, 10)\n    Output dimensions: (10, 10)\n    Plan: no plan"
end
