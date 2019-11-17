using FunctionOperators, LinearAlgebra, Test

@testset "normalizeExpression - Auxiliary.jl" begin
    @testset "normalizeExpression" begin
        normE(str) = FunctionOperators.normalizeExpression(str)
        @test normE("A * (B * C * D)' + (A * (B' * C * D)')'") ==
                normE("(B' * C * D) * A' + A * (B * C * D)'") ==
                "B' * C * D * A' + A * D' * C' * B'"
        @test normE("A * (A + ((B -C) -E) + (e - f))") ==
                normE("A * (((B -E) -C)+A + (e - f))") == 
                "A * ((e - f) + A + ((B - E) - C))"
        @test normE("q + (A + ((B -C) -E) + (e - f)) * W") ==
                normE("(A + ((B -C) -E) + (e - f)) * W + q") ==
                "q + (e * W - f * W) + A * W + ((B * W - E * W) - C * W)"
        @test normE("A * (A + ((B -C) -E) + (e - f)) * W") ==
                normE("A * (((B -E) -C) * W + A * W + (e - f) * W)") ==
                "A * ((e * W - f * W) + A * W + ((B * W - E * W) - C * W))"
        @test normE("(A + B) * (C + D)") == "B * (D + C) + A * (D + C)"
        @test normE("(A + B) * (C * D)") == normE("(A + B) * C * D") ==
                "B * C * D + A * C * D"
        @test normE("(a + b) * (A + B) * (C + D)") ==
                "b * (B * (D + C) + A * (D + C)) + a * (B * (D + C) + A * (D + C))"
    end
end;