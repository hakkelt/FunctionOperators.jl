using FunctionOperators, LinearAlgebra, Test, BenchmarkTools

data = [sin(i+j+k)^2 for i=1:300, j=1:300, k=1:50]
bOp₁ = FunctionOperator{Float64}(name="Op₁",
    forw = (buffer, x) -> buffer .= x.^2,
    backw = (buffer, x) -> broadcast!(sqrt, buffer, x),
    inDims = (300, 300, 50), outDims = (300, 300, 50))
weights = [sin((i-j)*l) + 1 for i=1:300, j=1:300, k=1:50, l=1:10]
bOp₂ = FunctionOperator{Float64}(name="Op₂",
    forw = (buffer,x) -> buffer .= reshape(x, 300, 300, 50, 1) .* weights,
    backw = (buffer,x) -> dropdims(sum!(reshape(buffer, 300, 300, 50, 1), x ./ weights), dims=4),
    inDims=(300, 300, 50), outDims=(300, 300, 50, 10))
combined = bOp₂ * (bOp₁ - 2.5*I) * bOp₁'
output = combined * data
function getAggregatedFunction()
    weights = [sin((i-j)*l) + 1 for i=1:300, j=1:300, k=1:50, l=1:10]
    buffer2 = Array{Float64}(undef, 300, 300, 50)
    buffer3 = Array{Float64}(undef, 300, 300, 50)
    buffer4 = Array{Float64}(undef, 300, 300, 50)
    (buffer, x) -> begin
        broadcast!(sqrt, buffer2, x)  # Of course, this two lines can be optimized to
        buffer3 .= buffer2 .^ 2       # (√x)^2 = |x|, but let's now avoid this fact
        broadcast!(-, buffer3, buffer3, broadcast!(*, buffer4, 2.5, buffer2))
        buffer .= reshape(buffer3, 300, 300, 50, 1) .* weights
    end
end
aggrFun = getAggregatedFunction()

@testset "Performance" begin
    t1 = @belapsed mul!(output, combined, data)
    t2 = @belapsed aggrFun(output, data)
    @test t1 / t2 ≈ 1 atol=0.05
end