using FunctionOperators, LinearAlgebra, Test

@testset "Functionality test" begin
    Op₁ = FunctionOperator{Float64}("Op₁",
        x -> x .^ 3, x -> cbrt.(x), (10,10), (10,10))
    Op₂ = FunctionOperator{Float64}("Op₂",
        x -> x .+ 2, x -> x .- 2, (10,10), (10,10))
    bOp₁ = FunctionOperator{Float64}("bOp₁",
        (b,x) -> b.=x.^3, (b,x) -> b.=cbrt.(x), (10,10), (10,10))
    bOp₂ = FunctionOperator{Float64}("bOp₂",
        (b,x) -> b.=x.+2, (b,x) -> b.=x.-2, (10,10), (10,10))
    w = reshape([1 2 3 4 5], 1, 1, 5)
    Op₃ = FunctionOperator{Float64}("Op₃",
        x -> x .* w, x -> x[:,:,1], (10,10), (10,10,5))
    Op₄ = FunctionOperator{Float64}("Op₄",
        x -> repeat(x, outer=(1,1,5)), x -> x[:,:,5], (10,10), (10, 10, 5))
    bOp₃ = FunctionOperator{Float64}("bOp₃",
        (b,x) -> broadcast!(*, b, reshape(x, 10, 10, 1), w), (b,x) -> b .= x[:,:,1], (10,10), (10,10,5))
    bOp₄ = FunctionOperator{Float64}("bOp₄",
        (b,x) -> b.=repeat(x, outer=(1,1,5)), (b,x) -> b .= x[:,:,5], (10,10), (10, 10, 5))
    Op₅ = FunctionOperator{Float64}("Op₅",
        x -> -x .^ 3, x -> -cbrt.(x), (10,10,5), (10,10,5))
    Op₆ = FunctionOperator{Float64}("Op₆",
        x -> x .+ 5, x -> x .- 5, (10,10,5), (10,10,5))
    bOp₅ = FunctionOperator{Float64}("bOp₅",
        (b,x) -> b.=-x.^3, (b,x) -> b.=-cbrt.(x), (10,10,5), (10,10,5))
    bOp₆ = FunctionOperator{Float64}("bOp₆",
        (b,x) -> b.=x.+5, (b,x) -> b.=x.-5, (10,10,5), (10,10,5))
    data₁ = [sin(i+j) for i=1:10, j=1:10]
    data₂ = [sin(i+j+k) for i=1:10, j=1:10, k=1:5]
    function manual_tests()
        @test Op₁ * (ones(10,10)*2) == ones(10,10)*8
        @test Op₁' * (ones(10,10)*8) == ones(10,10)*2
        @test Op₁ * I * (ones(10,10)*2) == ones(10,10)*8
        @test Op₁' * I * (ones(10,10)*8) == ones(10,10)*2
        @test I * Op₁ * (ones(10,10)*2) == ones(10,10)*8
        @test I * Op₁' * (ones(10,10)*8) == ones(10,10)*2
        @test Op₁ * 2 * (ones(10,10)*2) == ones(10,10)*64
        @test Op₁' * 2 * (ones(10,10)*4) == ones(10,10)*2
        @test 2 * Op₁ * (ones(10,10)*2) == ones(10,10)*16
        @test 2 * Op₁' * (ones(10,10)*8) == ones(10,10)*4
        @test Op₃ * Op₁ * (ones(10,10)*2) == ones(10,10)*8 .* w
        @test (Op₃ * Op₁)' * (ones(10,10)*8 .* w) == Op₁' * Op₃' * (ones(10,10)*8 .* w)
        @test (Op₃ * Op₁)' * (ones(10,10)*8 .* w) == ones(10,10)*2
        @test (Op₃ + Op₄) * (ones(10,10)*2) == Op₃ * (ones(10,10)*2) + Op₄ * (ones(10,10)*2)
        @test (Op₃ - Op₄) * (ones(10,10)*2) == Op₃ * (ones(10,10)*2) - Op₄ * (ones(10,10)*2)
        @test 3I * Op₃ * (ones(10,10)*2) == (ones(10,10)*2 .* w) * 3
        @test Op₃ * 3I * (ones(10,10)*2) == ones(10,10)*6 .* w
        @test (Op₃ * 3I)' * (ones(10,10)*2 .* w) == ones(10,10)*6
        @test (Op₅ + 3I) * (ones(10,10,5)*2) == Op₅ * (ones(10,10,5)*2) + (ones(10,10,5)*6)
        @test (Op₅ - 3I) * (ones(10,10,5)*2) == Op₅ * (ones(10,10,5)*2) - (ones(10,10,5)*6)
        @test (3I + Op₅) * (ones(10,10,5)*2) == (ones(10,10,5)*6) + Op₅ * (ones(10,10,5)*2)
        @test (3I - Op₅) * (ones(10,10,5)*2) == (ones(10,10,5)*6) - Op₅ * (ones(10,10,5)*2)
        output = zeros(10, 10)
        @test Op₁ * (ones(10,10)*2) == mul!(output, Op₁, ones(10,10)*2)
        @test Op₁' * (ones(10,10)*2) == mul!(output, Op₁', ones(10,10)*2)
        @test Op₁ * bOp₂ * (ones(10,10)*2) == mul!(output, Op₁ * bOp₂, ones(10,10)*2)
        @test (Op₁ * bOp₂)' * (ones(10,10)*2) == mul!(output, (Op₁ * bOp₂)', ones(10,10)*2)
        combined = bOp₁ * Op₂
        @test mul!(output, combined, ones(10,10)*2) == mul!(output, combined, ones(10,10)*2)
        combined = (bOp₁ * Op₂)'
        @test mul!(output, combined, ones(10,10)*2) == mul!(output, combined, ones(10,10)*2)
    end
    @testset "Fidelity (manually checked)" begin
        @testset "Without automatic reshape" begin
            manual_tests()
        end
        @testset "With automatic reshape" begin
            FunctionOperators_global_settings.auto_reshape = true
            manual_tests()
            FunctionOperators_global_settings.auto_reshape = false
        end
    end
    @testset "Adjoint of addition/substraction" begin
        @test_throws ErrorException (Op₃ + Op₄)' * ones(10,10,5)
        @test_throws ErrorException (Op₃ - Op₄)' * ones(10,10,5)
    end
    @testset "Automated" begin
        @testset "Combine" begin
            function combineMul(item1, item2)
                if item1.op.inDims ≠ item2.op.outDims
                    @test_throws DimensionMismatch item1.op * item2.op
                    missing
                else
                    (op = item1.op * item2.op,
                    forw = x -> (x₁ = item2.op * x; item1.op * x₁),
                    backw = x -> (x₁ = item1.op' * x; item2.op' * x₁),
                    hasAddOrSub = item1.hasAddOrSub || item2.hasAddOrSub)
                end
            end
            function combineMulScalingRight(item1)
                (op = item1.op * 5I,
                forw = x -> (x₁ = 5 * x; item1.op * x₁),
                backw = x -> (x₁ = item1.op' * x; 5 * x₁),
                hasAddOrSub = item1.hasAddOrSub)
            end
            function combineMulScalingLeft(item1)
                (op = 4I * item1.op,
                forw = x -> (x₁ = item1.op * x; 4 * x₁),
                backw = x -> (x₁ = 4 * x; item1.op' * x₁),
                hasAddOrSub = item1.hasAddOrSub)
            end
            function combineAdd(item1, item2)
                if item1.op.inDims ≠ item2.op.inDims || item1.op.outDims ≠ item2.op.outDims
                    @test_throws DimensionMismatch item1.op + item2.op
                    missing
                else
                    (op = item1.op + item2.op,
                    forw = x -> (x₁ = item1.op * x; x₂ = item2.op * x; x₁ + x₂),
                    backw = x -> throw(AssertionError("This should not be invoked")),
                    hasAddOrSub = true)
                end
            end
            function combineAddScalingRight(item1)
                if item1.op.inDims ≠ item1.op.outDims
                    @test_throws DimensionMismatch item1.op + 6I
                    missing
                else
                    (op = item1.op + 6I,
                    forw = x -> (x₁ = item1.op * x; x₂ = 6 * x; x₁ + x₂),
                    backw = x -> throw(AssertionError("This should not be invoked")),
                    hasAddOrSub = true)
                end
            end
            function combineAddScalingLeft(item1)
                if item1.op.inDims ≠ item1.op.outDims
                    @test_throws DimensionMismatch 7I + item1.op
                    missing
                else
                    (op = 7I + item1.op,
                    forw = x -> (x₁ = 7 * x; x₂ = item1.op * x; x₁ + x₂),
                    backw = x -> throw(AssertionError("This should not be invoked")),
                    hasAddOrSub = true)
                end
            end
            function combineSub(item1, item2)
                if item1.op.inDims ≠ item2.op.inDims || item1.op.outDims ≠ item2.op.outDims
                    @test_throws DimensionMismatch item1.op - item2.op
                    missing
                else
                    (op = item1.op - item2.op,
                    forw = x -> (x₁ = item1.op * x; x₂ = item2.op * x; x₁ - x₂),
                    backw = x -> throw(AssertionError("This should not be invoked")),
                    hasAddOrSub = true)
                end
            end
            function combineSubScalingRight(item1)
                if item1.op.inDims ≠ item1.op.outDims
                    @test_throws DimensionMismatch item1.op - 3I
                    missing
                else
                    (op = item1.op - 3I,
                    forw = x -> (x₁ = item1.op * x; x₂ = 3 * x; x₁ - x₂),
                    backw = x -> throw(AssertionError("This should not be invoked")),
                    hasAddOrSub = true)
                end
            end
            function combineSubScalingLeft(item1)
                if item1.op.inDims ≠ item1.op.outDims
                    @test_throws DimensionMismatch 11I - item1.op
                    missing
                else
                    (op = 11I - item1.op,
                    forw = x -> (x₁ = 11 * x; x₂ = item1.op * x; x₁ - x₂),
                    backw = x -> throw(AssertionError("This should not be invoked")),
                    hasAddOrSub = true)
                end
            end
            function combineAdjoint(item1)
                if item1.hasAddOrSub
                    @test_throws ErrorException item1.op' * (item1.outDims == size(data₁) ? data₁ : data₂)
                    missing
                else
                    (op = item1.op',
                    forw = item1.backw,
                    backw = item1.forw,
                    hasAddOrSub = false)
                end
            end
            function allTypeOfCombinationOfOne(item1)
                [combineMulScalingRight(item1), combineMulScalingLeft(item1),
                 combineAddScalingRight(item1), combineAddScalingLeft(item1),
                 combineSubScalingRight(item1), combineSubScalingLeft(item1),
                 combineAdjoint(item1)]
            end
            function allTypeOfCombinationOfTwo(item1, item2)
                [combineMul(item1, item2), combineAdd(item1, item2), combineSub(item1, item2)]
            end
            function Cartesian_product_with_itself(list)
                new_list1 = [allTypeOfCombinationOfOne(item1) for item1 in list]
                new_list2 = [allTypeOfCombinationOfTwo(item1, item2)
                    for item1 in list, item2 in list]
                collect(skipmissing(vcat(list, new_list1..., new_list2...)))
            end
            Ops = [Op₁, bOp₁, Op₃, bOp₃, Op₅, bOp₅]
            global list
            list = [(op = op, forw = x -> op * x, backw = x -> op' * x, hasAddOrSub = false)
                for op in Ops]
            list = Cartesian_product_with_itself(list)
            # it would be nice to repeat this step, but it would be never completed...
            #list = Cartesian_product_with_itself(list)
            # instead:
            function combine_special_cases(list)
                new_list = []
                push!(new_list, [combineMul(item1, list[1]) for item1 in list]...)
                push!(new_list, [combineMul(list[1], item1) for item1 in list]...)
                push!(new_list, [combineMul(item1, list[2]) for item1 in list]...)
                push!(new_list, [combineMul(list[2], item1) for item1 in list]...)
                push!(new_list, [combineMul(item1, list[3]) for item1 in list]...)
                push!(new_list, [combineMul(list[3], item1) for item1 in list]...)
                push!(new_list, [combineMul(item1, list[4]) for item1 in list]...)
                push!(new_list, [combineMul(list[4], item1) for item1 in list]...)
                spec₁ = combineAdd(list[1], list[2])
                push!(new_list, [combineMul(item1, spec₁) for item1 in list]...)
                push!(new_list, [combineAdd(item1, spec₁) for item1 in list]...)
                push!(new_list, [combineMul(spec₁, item1) for item1 in list]...)
                spec₂ = combineAdd(list[2], list[1])
                push!(new_list, [combineMul(item1, spec₂) for item1 in list]...)
                push!(new_list, [combineSub(item1, spec₁) for item1 in list]...)
                push!(new_list, [combineMul(spec₂, item1) for item1 in list]...)
                list = collect(skipmissing(vcat(list, new_list...)))
                new_list = []
                push!(new_list, [combineAdjoint(item1) for item1 in list]...)
                collect(skipmissing(vcat(list, new_list...)))
            end
            list = combine_special_cases(list)
            println("Number of generated operators: ", length(list))
        end
        @testset "Fidelity" begin
            global list
            getName(op) = op isa FunctionOperator && op.adjoint ? op.name*"'" : op.name
            normName(str) = replace(FunctionOperators.normalizeExpression(getName(str)), "b" => "")
            results = [(name = getName(op.op),
                        normalized_name = normName(op.op),
                        mult_res = op.op * (op.op.inDims == size(data₁) ? data₁ : data₂),
                        forw_res = op.forw(op.op.inDims == size(data₁) ? data₁ : data₂),
                        plan = op.op isa FunctionOperator ? op.op.name : op.op.plan_string)
                            for op in list]
            for res in results
                res.mult_res ≠ res.forw_res && println(res.name, ", ", res.plan)
                @test res.mult_res == res.forw_res
            end
            counter = 0
            for (i,res1) in enumerate(results), (j,res2) in enumerate(results)
                i >= j && continue
                if res1.normalized_name == res2.normalized_name
                    counter += 1
                    res1.mult_res ≠ res2.mult_res && println(i, ", ", res1.name, ", ", res1.plan, "\n", j, res2.name, ", ", res2.plan)
                    @test res1.mult_res == res2.mult_res
                end
            end
            println("Pairwise matches between operators: ", counter, " (match means same functionality that checked for same result)")
        end
    end
end;