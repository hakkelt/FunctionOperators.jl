using FunctionOperators, Test

@testset "Macro - Auxiliary.jl" begin
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
        result, var1, var2 = rand(3,3), rand(3,3), rand(3,3)
        @♻ for i=1:5
            @🔃 result = var1 * var2
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
end;