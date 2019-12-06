using FunctionOperators, MacroTools, OffsetArrays, LinearAlgebra, Test, BenchmarkTools

d = rand(10, 3, 2)im
Ω = FunctionOperator{Complex{Float64}}(x -> x, x -> x, (10, 3, 2), (10, 3, 2))
Q = FunctionOperator{Complex{Float64}}(x -> x, x -> x, (10, 3, 2), (10, 3, 2))
C = FunctionOperator{Complex{Float64}}(x -> repeat(x, outer=(1,1,2)), x -> x[:,:,1], (10, 3), (10, 3, 2))
T = FunctionOperator{Complex{Float64}}(x -> x, x -> x, (10, 3), (10, 3))

samp = rand(10, 3);
E = Ω * Q * C
normₙ(A) = sum(svdvals(A))
norm₁(A) = norm(A, 1)
norm₂(A) = norm(A, 2)

pos(x) = x < 0 ? zero(x) : x
Λ!(v,p) = @. v = sign(v) * pos(abs(v) - p)

SVT(A,p) = begin
    F = svd(A)
    F.U*Diagonal(Λ!(F.S,p))*F.Vt
end

function getCostFunc(E::FunOp, T::FunOp, d::Array{Complex{Float64},3})
    (L,S,d,λ_L,λ_S) -> 0.5*norm₂(E*(L + S) - d)^2 + λ_L*normₙ(L) + λ_S*norm₁(T * S)
end
cost = getCostFunc(E, T, d)

function AL_2(d::Array{Complex{Float64}, 3},  # measurement data
        Ω::FunOp,                             # sampling operator
        Q::FunOp,                             # Fourier operator
        C::FunOp,                             # coil sensitivity operator
        T::FunOp;                             # sparsifying operator
        scale_L::Float64 = 1.,
        scale_S::Float64 = 1.,
        λ_L::Float64 = 0.01,
        λ_S::Float64 = 0.05,
        δ₁::Complex{Float64} = 1im / 10.,
        δ₂::Float64 = 1. / 100,
        iterL::Int64 = 3,
        iterS::Int64 = iterL,
        N::Int64 = 10)

    #Initialize
    E = Ω * Q * C
    x₀ = E' * d
    L = copy(x₀)
    S = zeros(Complex{Float64}, size(L))
    X = L + S
    V₁ = zeros(Complex{Float64}, size(d))
    V₂ = zeros(Complex{Float64}, size(L))
    Z_scaler = 1 ./ (reshape(samp, size(samp)..., 1) .+ δ₁)

    cost_vec = OffsetVector{Float64}(undef, 0:N)
    cost_vec[0] = cost(L, S, d, scale_L*λ_L, scale_S*λ_S)

    for k in 1:N
        Z = Z_scaler .* (Ω' * d + δ₁*(Q * C * X - V₁))
        X = δ₁/(δ₁+δ₂) * C' * Q' * (Z + V₁) + δ₂/(δ₁+δ₂) * (L + S - V₂)
        L = SVT(X - S + V₂, scale_L * λ_L / δ₂)
        S = T' * Λ!(T * (X - L + V₂), scale_S * λ_S / δ₂)
        if k == 3
            V₁ += Z - Q * C * X
            V₂ += X - L - S
        end

        cost_vec[k] = cost(L, S, d, scale_L*λ_L, scale_S*λ_S)
    end

    L + S, cost_vec
end

function getCostFunc_recycle(E::FunOp, T::FunOp, d::Array{Complex{Float64},3})
    @recycle(arrays=[L,S,d], funops=[E,t], numbers=[λ_L,λ_S],
        (L,S,d,λ_L,λ_S) -> 0.5*norm₂(E*(L + S) - d)^2 + λ_L*normₙ(L) + λ_S*norm₁(T * S))
end
const cost_recycle = getCostFunc_recycle(E, T, d)

function AL_2_recycle(d::Array{Complex{Float64}, 3},  # measurement data
        Ω::FunOp,                             # sampling operator
        Q::FunOp,                             # Fourier operator
        C::FunOp,                             # coil sensitivity operator
        T::FunOp;                             # sparsifying operator
        scale_L::Float64 = 1.,
        scale_S::Float64 = 1.,
        λ_L::Float64 = 0.01,
        λ_S::Float64 = 0.05,
        δ₁::Complex{Float64} = 1im / 10.,
        δ₂::Float64 = 1. / 100,
        iterL::Int64 = 3,
        iterS::Int64 = iterL,
        N::Int64 = 10)

    #Initialize
    E = Ω * Q * C
    x₀ = E' * d
    L = copy(x₀)
    S = zeros(Complex{Float64}, size(L))
    X = L + S
    V₁ = zeros(Complex{Float64}, size(d))
    V₂ = zeros(Complex{Float64}, size(L))
    Z_scaler = 1 ./ (reshape(samp, size(samp)..., 1) .+ δ₁)

    cost_vec = OffsetVector{Float64}(undef, 0:N)
    cost_vec[0] = cost_recycle(L, S, d, scale_L*λ_L, scale_S*λ_S)

    @recycle for k in 1:N
        Z = Z_scaler .* (Ω' * d + δ₁*(Q * C * X - V₁))
        X = δ₁/(δ₁+δ₂) * C' * Q' * (Z + V₁) + δ₂/(δ₁+δ₂) * (L + S - V₂)
        L = SVT(X - S + V₂, scale_L * λ_L / δ₂)
        S = T' * Λ!(T * (X - L + V₂), scale_S * λ_S / δ₂)
        if k == 3
            V₁ += Z - Q * C * X
            V₂ += X - L - S
        end

        cost_vec[k] = cost_recycle(L, S, d, scale_L*λ_L, scale_S*λ_S)
    end

    L + S, cost_vec
end

@testset "recycle" begin
    res, cost = AL_2(d, Ω, Q, C, T)
    res_recycle, cost_recycle = AL_2_recycle(d, Ω, Q, C, T)
    @test res == res_recycle
    @test cost == cost_recycle
    @test @belapsed(AL_2(d, Ω, Q, C, T)) / @belapsed(AL_2_recycle(d, Ω, Q, C, T)) > 2.
end
