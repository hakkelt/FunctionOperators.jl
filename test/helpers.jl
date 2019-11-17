using FunctionOperators, LinearAlgebra, Test

@testset "Helpers.jl" begin
    Op₁ = FunctionOperator{Float64}(x -> x, (1,), (1,))
    Op₂ = FunctionOperator{Int64}(x -> x, (1,), (1,))
    Op₃ = FunctionOperator{Float64}(x -> x, (1,), (1,))
    Op₄ = FunctionOperator{Float64}(x -> x, (1,), (2,))
    buffer = Array{Float64}(undef, 1)
    @testset "eltype" begin
        @test eltype(Op₁) == Float64
        @test eltype(Op₁ * Op₃) == Float64
    end
    @testset "assertions" begin
        @testset "TypeError" begin
            @test_throws TypeError Op₁ * Op₂
            @test_throws TypeError Op₁ + Op₂
            @test_throws TypeError Op₁ - Op₂
            @test_throws TypeError (Op₁ + Op₁) * Op₂
            @test_throws TypeError (Op₁ + Op₁) + Op₂
            @test_throws TypeError (Op₁ + Op₁) - Op₂
            @test_throws TypeError Op₁ * (Op₂ + Op₂)
            @test_throws TypeError Op₁ + (Op₂ + Op₂)
            @test_throws TypeError Op₁ - (Op₂ + Op₂)
            @test_throws TypeError (Op₁ + Op₁) * (Op₂ + Op₂)
            @test_throws TypeError (Op₁ + Op₁) + (Op₂ + Op₂)
            @test_throws TypeError (Op₁ + Op₁) - (Op₂ + Op₂)
            @test_throws TypeError mul!(Array{Int64}(undef, 1), Op₁, [1.])
            @test_throws TypeError mul!(Array{Int64}(undef, 1), Op₁ * Op₂, [1.])
            @test_throws TypeError mul!(buffer, Op₁, [1])
            @test_throws TypeError mul!(buffer, Op₁ * Op₂, [1])
        end
        @testset "DimensionError" begin
            @test_throws DimensionMismatch Op₁ * [1.,2.]
            @test_throws DimensionMismatch Op₁ * Op₃ * [1.,2.]
            @test_throws DimensionMismatch (Op₁ + Op₃) * [1.,2.]
            @test_throws DimensionMismatch (Op₁ - Op₃) * [1.,2.]
            @test_throws DimensionMismatch Op₃ * Op₄
            @test_throws DimensionMismatch (Op₄ + Op₃)
            @test_throws DimensionMismatch (Op₄ - Op₃)
            @test_throws DimensionMismatch (Op₄ + I)
            @test_throws DimensionMismatch (Op₄ - I)
            @test_throws DimensionMismatch (Op₄ + 3I)
            @test_throws DimensionMismatch (Op₄ - 3I)
            @test_throws DimensionMismatch mul!(buffer, Op₁, [1., 2.])
            @test_throws DimensionMismatch mul!(buffer, Op₁ * Op₃, [1.,2.])
            @test_throws DimensionMismatch mul!(Array{Float64}(undef, 2), Op₁, [1.])
            @test_throws DimensionMismatch mul!(Array{Float64}(undef, 2), Op₁ * Op₃, [1.])
        end
    end
end;