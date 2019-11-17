using FunctionOperators, Test

@testset "Constructors - StructDefs.jl" begin
    @testset "Proper constructors" begin
        @testset "Keyword constructors" begin
            @test FunctionOperator{Float64}(name = "Op₁",
                forw = x -> x, backw = x -> x,
                inDims = (1,), outDims = (1,)) isa FunOp
            @test FunctionOperator{Float64}(
                forw = x -> x, backw = x -> x,
                inDims = (1,), outDims = (1,)) isa FunOp
            @test FunctionOperator{Float64}(name = "Op₁",
                forw = x -> x,
                inDims = (1,), outDims = (1,)) isa FunOp
            @test FunctionOperator{Float64}(forw = x -> x,
                inDims = (1,), outDims = (1,)) isa FunOp
        end
        @testset "Positional constructors" begin
            @test FunctionOperator{Float64}("Op₁", x -> x, x -> x,
                (1,), (1,)) isa FunOp
            @test FunctionOperator{Float64}(x -> x, x -> x,
                (1,), (1,)) isa FunOp
            @test FunctionOperator{Float64}("Op₁", x -> x,
                (1,), (1,)) isa FunOp
            @test FunctionOperator{Float64}(x -> x,
                (1,), (1,)) isa FunOp
        end
    end
    @testset "Missing value" begin
        @test_throws ErrorException FunctionOperator{Float64}(name = "Op₁",
            backw = x -> x,
            inDims = (1,), outDims = (1,))
        @test_throws ErrorException FunctionOperator{Float64}(name = "Op₁",
            forw = x -> x, backw = x -> x,
            outDims = (1,))
        @test_throws ErrorException FunctionOperator{Float64}(name = "Op₁",
            forw = x -> x, backw = x -> x,
            inDims = (1,))
    end
    @testset "No arguments for forw" begin
        @testset "Keyword constructors" begin
            @test_throws AssertionError FunctionOperator{Float64}(name = "Op₁",
                forw = () -> x, backw = x -> x,
                inDims = (1,), outDims = (1,))
            @test_throws AssertionError FunctionOperator{Float64}(
                forw = () -> x, backw = x -> x,
                inDims = (1,), outDims = (1,))
            @test_throws AssertionError FunctionOperator{Float64}(name = "Op₁",
                forw = () -> x,
                inDims = (1,), outDims = (1,))
            @test_throws AssertionError FunctionOperator{Float64}(forw = () -> x,
                inDims = (1,), outDims = (1,))
        end
        @testset "Positional constructors" begin
            @test_throws AssertionError FunctionOperator{Float64}("Op₁", () -> x, x -> x,
                (1,), (1,))
            @test_throws AssertionError FunctionOperator{Float64}(() -> x, x -> x,
                (1,), (1,))
            @test_throws AssertionError FunctionOperator{Float64}("Op₁", () -> x,
                (1,), (1,))
            @test_throws AssertionError FunctionOperator{Float64}(() -> x,
                (1,), (1,))
        end
    end
    @testset "Too many arguments for forw" begin
        @testset "Keyword constructors" begin
            @test_throws AssertionError FunctionOperator{Float64}(name = "Op₁",
                forw = (x,y,z) -> x, backw = x -> x,
                inDims = (1,), outDims = (1,))
            @test_throws AssertionError FunctionOperator{Float64}(
                forw = (x,y,z) -> x, backw = x -> x,
                inDims = (1,), outDims = (1,))
            @test_throws AssertionError FunctionOperator{Float64}(name = "Op₁",
                forw = (x,y,z) -> x,
                inDims = (1,), outDims = (1,))
            @test_throws AssertionError FunctionOperator{Float64}(forw = (x,y,z) -> x,
                inDims = (1,), outDims = (1,))
        end
        @testset "Positional constructors" begin
            @test_throws AssertionError FunctionOperator{Float64}("Op₁", (x,y,z) -> x,
                x -> x, (1,), (1,))
            @test_throws AssertionError FunctionOperator{Float64}((x,y,z) -> x, x -> x,
                (1,), (1,))
            @test_throws AssertionError FunctionOperator{Float64}("Op₁", (x,y,z) -> x,
                (1,), (1,))
            @test_throws AssertionError FunctionOperator{Float64}((x,y,z) -> x,
                (1,), (1,))
        end
    end
    @testset "Forw has more arguments as backw" begin
        @testset "Keyword constructors" begin
            @test_throws AssertionError FunctionOperator{Float64}(name = "Op₁",
                forw = (x,y) -> x.^3, backw = x -> x,
                inDims = (1,), outDims = (1,))
            @test_throws AssertionError FunctionOperator{Float64}(
                forw = (x,y) -> x.^3, backw = x -> x,
                inDims = (1,), outDims = (1,))
        end
        @testset "Positional constructors" begin
            @test_throws AssertionError FunctionOperator{Float64}("Op₁", (x,y) -> x.^3,
                x -> x, (1,), (1,))
            @test_throws AssertionError FunctionOperator{Float64}((x,y) -> x.^3, x -> x,
                (1,), (1,))
        end
    end
    @testset "Unique default name" begin
        @test FunctionOperator{Float64}(x->x,(1,),(1,)) ≠
            FunctionOperator{Float64}(x->x,(1,),(1,))
    end
    @testset "Undefined backw" begin
        Op₁ = FunctionOperator{Float64}(x->x,(1,),(1,))
        @test_throws ErrorException Op₁' * [1.]
    end
end;