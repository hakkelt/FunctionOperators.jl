using FunctionOperators, LinearAlgebra, Test
@testset "Auxiliary.jl" begin
    @testset "normalizeExpression" begin
        normE(str) = FunctionOperators.normalizeExpression(str)
        @test normE("A * (B * C * D)' + (A * (B' * C * D)')'") ==
                normE("(B' * C * D) * A' + A * (B * C * D)'") ==
                normE("B' * C * D * A' + A * D' * C' * B'")
        @test normE("A * (A + ((B -C) -E) + (e - f))") ==
                normE("A * (((B -E) -C)+A + (e - f))") == 
                normE("A * ((e - f) + A + ((B - E) - C))")
        @test normE("q + (A + ((B -C) -E) + (e - f)) * W") ==
                normE("(A + ((B -C) -E) + (e - f)) * W + q") ==
                normE("q + (e * W - f * W) + A * W + ((B * W - E * W) - C * W)")
        @test normE("A * (A + ((B -C) -E) + (e - f)) * W") ==
                normE("A * (((B -E) -C) * W + A * W + (e - f) * W)") ==
                normE("A * ((e * W - f * W) + A * W + ((B * W - E * W) - C * W))")
        @test normE("(A + B) * (C + D)") == "B * (D + C) + A * (D + C)"
        @test normE("(A + B) * (C * D)") == normE("(A + B) * C * D") ==
                normE("B * C * D + A * C * D")
        @test normE("(a + b) * (A + B) * (C + D)") ==
                normE("b * (B * (D + C) + A * (D + C)) + a * (B * (D + C) + A * (D + C))")
        @test normE("A + B + (E + D) + C") == normE("A + B + E + D + C")
        @test normE("(A - B) * C * D * E") == normE("A * C * D * E - B * C * D * E")
        @test normE("A * (D + C + B) * D * E * F") ==
                normE("A * (D * D * E * F + C * D * E * F + B * D * E * F)")
        @test normE("A * B * C * (E - F) * (D + E)") ==
                normE("A * B * C * (E * (D + E) - F * (D + E))")
        @test normE("A - (B - C)") == normE("A - B + C") == normE("C + A - B")
        # Well, I need to completely reorganize my code to support the following case, so I don't support it :(
        @test normE("A + B + (C - E)") == normE("(A + B + C) - E")
    end
    @testset "Equality" begin
        Op₁ = FunctionOperator{Float64}("Op₁", x -> x, x -> x, (1,), (1,))
        Op₂ = FunctionOperator{Float64}("Op₂", x -> x, x -> x, (1,), (1,))
        @test Op₁ != Op₂
        @test Op₁ + Op₂ != Op₂
        @test Op₁ != Op₂ + Op₂
        @test Op₁ + Op₂ != Op₂ + Op₂
        @test Op₁ * Op₂ != Op₂ * Op₁
        @test Op₁ == Op₁
        @test Op₁ + Op₂ == Op₂ + Op₁
        @test Op₁ * Op₂ == Op₁ * Op₂
    end
    @testset "Macro" begin
        @testset "🔝 marker" begin
            result, var1, var2, var3 = rand(4)
            @♻ for i=1:5
                result = 🔝(var1 + var2) * var3
            end
            @test 🔝_1 == var1 + var2
            @test result == (var1 + var2) * var3
        end
        @testset "🔃 marker" begin
            result, var1, var2, var3 = rand(3,3), rand(3,3), rand(3,3), rand(3,3)
            @♻ for i=1:5
                var2 .= rand(3,3)
                result .= var1 * 🔃(var2 + var3)
                @test 🔃_1 == var2 + var3
            end
            @test result == var1 * (var2 + var3)
            @♻ for i=1:5
                result = var1 * 🔃(var2 * var3)
                @test 🔃_1 == var2 * var3
            end
            @test result == var1 * (var2 * var3)
        end
        @testset "@🔃 marker" begin
            var1, var2 = rand(3,3), rand(3,3)
            @♻ for i=1:5
                @🔃 result = var1 * var2
            end
            @test result == var1 * var2
            var1, var2 = rand(3,3), rand(3,3)
            @♻ for i=1:5
                @🔃 result .= var1 * var2
            end
            @test result == var1 * var2
        end
        @testset "nesting" begin
            result, var1, var2, var3 = rand(3,3), rand(3,3), rand(3,3), rand(3,3)
            @♻ for i=1:5
                @🔃 result = 🔃(🔝(var1 + var2) * var3)
                @test 🔃_1 == (var1 + var2) * var3
            end
            @test 🔝_1 == var1 + var2
            @test result == (var1 + var2) * var3
        end
    end
end;