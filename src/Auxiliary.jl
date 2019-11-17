# ----------------------------------------------------------
# ---------------  Auxiliary functionalities  --------------
# ----------------------------------------------------------

"""
Manually set the plan of a FunctionOperator
Arguments:
 - `FO` composite FunctionOperator to be changed
 - `f` manually defined plan (function with two arguments, first is the output buffer, second is the input array)
 - `f_str` (Optional) string representation of the plan
"""
setPlan(FO::FunctionOperatorComposite, f::Function, f_str::String = "manually defined") = begin
    @assert nargs(f) == 3  "plan must accept two arguments!"
    FO.plan_function = f
    FO.plan_string = f_str
end

# --------- Equality check -----------

# Expand arithmetic expression trees
function expand(expr)
    sortExprList(ExprList) = sort(ExprList, by = x -> string(x), rev = true)
    adj(e) = (e isa Expr && string(e.head) == "'") ? e.args[1] : Expr(Symbol("'"), e)
    MacroTools.postwalk(x -> begin
        # Adjoint expansion. Eg: (op1 * op2)' -> op2' * op1'
        if @capture(x, (e1_ * e2__)')
            Expr(:call, :*, [adj(e) for e in reverse(e2)]..., adj(e1))
        # Multiplication associativity
        elseif @capture(x, (e1_ * e2__) * e3__)
            Expr(:call, :*, e1, e2..., e3...)
        elseif @capture(x, e1__ * (e2_ * e3__))
            Expr(:call, :*, e1..., e2, e3...)
        # Remove unnecessary parentheses around addition by associativity.
        # Eg: op1 + (op2 + op3) -> op1 + op2 + op3
        elseif @capture(x, e1__ + e2_)
            list = [e1..., e2]
            new_list = []
            for item in list
                if @capture(item, E1__ + E2_)
                    new_list = vcat(new_list, E1, E2)
                else
                    push!(new_list, item)
                end
            end
            Expr(:call, :+, sortExprList(new_list)...)
        # Expandion by distributivity. Eg: (op1 ± op2) * op3 -> op1 * op3 ± op2 * op3
        elseif @capture(x, (e1__ + e2_) * (e3_))
            list = sortExprList([e1..., e2])
            Expr(:call, :+, sortExprList([Expr(:call, :*, e, e3) for e in list])...)
        elseif @capture(x, (e1__ + e2_) * e3__)
            list = sortExprList([e1..., e2])
            Expr(:call, :+, sortExprList([Expr(:call, :*, e, e3...) for e in list])...)
        elseif @capture(x, e0__ * (e1__ + e2_) * (e3_))
            list = sortExprList([e1..., e2])
            Expr(:call, :*, e0...,
                    Expr(:call, :+, sortExprList([Expr(:call, :*, e, e3) for e in list])...))
        elseif @capture(x, e0_ * (e1__ + e2_) * e3__) && length(e3) > 0
            list = sortExprList([e1..., e2])
            Expr(:call, :*, e0,
                Expr(:call, :+, sortExprList([Expr(:call, :*, e, e3...) for e in list])...))
        # Substraction as negation
        elseif @capture(x, -(e1_ * e2__))
            Expr(:call, :*, Expr(:call, :-, e1), e2...)
        elseif @capture(x, -(e1_ + e2__))
            Expr(:call, :+, Expr(:call, :-, e1), [Expr(:call, :-, e) for e in e2]...)
        elseif @capture(x, -(e1_ - e2_))
            Expr(:call, :+, Expr(:call, :-, e1), e2)
        elseif @capture(x, - -e2_)
            e2
        elseif @capture(x, e1_ - e2_)
            Expr(:call, :+, e1, Expr(:call, :-, e2))
        else
            x
        end
    end, expr)
end

# Normalize (expand fully) an arithmetic expression given as a string
function normalizeExpression(str)
    expr = Meta.parse(str) # I use the Julia parser to parse my simple arithmetical expressions
    # Not too elegant solution, I know...
    # But even complicated expressions can be fully expanded within a couple of iterations
    for i = 1:30
        new_expr = expand(expr)
        string(new_expr) == string(expr) && break
        expr = new_expr
    end
    string(expr)
end

"""
Equality check based on name

**HEADS UP!** This works only when operators with the same name has also the same functionality!

It performs basic arithmetic transformations on the expressions, so it recognizes even some less obvious equalities. The rules it uses:
 - Associativity: ``op1 * op2 * op3 = (op1 * op2) * op3 = op1 * (op2 * op3)``, ``op1 + op2 + op3 = (op1 + op2) + op3 = op1 + (op2 + op3)``, ``op1 + (op2 - op3) == (op1 + op2) - op3``, ``op1 - (op2 + op3) == (op1 - op2) - op3``
 - Commutativity: ``op1 - op2 - op3 = op1 - op3 - op2``, ``op1 + op2 = op2 + op1``
 - Distributivity: ``(op1 + op2) * op3 = op1 * op3 + op2 * op3`` (Note that ``op1 * (op2 + op3) ≠ op1 * op2 + op1 * op3``)
"""
Base.:(==)(FM1::FunctionOperatorComposite, FM2::FunctionOperatorComposite) =
    normalizeExpression(FM1.name) == normalizeExpression(FM2.name)

# --------- Recycling macro -----------
# Preallocates arrays for the output of different operations

"""
**Recycling macro**: Reduce the number of allocations inside a for loop by preallocation of arrays for the outputs of marked operations. Markers: `@♻` (`\\:recycle:`), `🔝` (`\\:top:`), `🔃` (`\\:arrows_clockwise:`), and `@🔃`

Macro @♻ should be placed right before a for loop, and then it executes the following substitutions:
 - **Expressions marked by `🔝`:**
They are going to be calculated before the loop, the result is stored in a variable, and the expression will be replaced by that variable. It also can be useful when a constant expression is used in the loop, but the idea behind creating that substitution is to allow caching of composite FunctionMatrices. Eg:
```julia
@♻ for i=1:5
    result = 🔝((FuncOp₁ + 2I) * FuncOp₂) * data
end
```
will be transformed to 
```julia
🔝_1 = (FuncOp₁ + 2I) * FuncOp₂
for i = 1:5
    result = 🔝_1 * data
end
```
so that way plan is calculated only once, and also buffers for intermediate results of the composite operator are allocated once.

 - **Expressions marked by `🔃`:**
They are going to be calculated before the loop (to allocate an array to store the result), but the expression is also evaluated in each loop iteration. The difference after the substitution is that the result of the expression is always saved to the preallocated array. Eg:
```julia
@♻ for i=1:5
    result = FuncOp₁ * 🔃(A + B)
end
```
will be transformed to 
```julia
🔃_1 = A + B
for i = 1:5
    result = FuncOp₁ * @.(🔃_1 = A + B)
end
```
This transformation first allocates an array named `🔃_1`, and then in every iteration it is recalculated, saved to `🔃_1`, and the this value is used for the rest of the operation (i.e.: `FuncOp₁ * 🔃_1`. Note that `@.` macro is inserted before the inline assignment. This is needed otherwise `A + B` would allocate a new array before it is stored in `🔃_1`. **Warning!** It can break your code, e.g. `@.(🔃_1 = A * B) ≠ (🔃_1 = A .* B)` {matrix multiplication vs. elementwise multiplication}! On the other hand, when the marked expression consists only a multiplication, then it is transformed into a call of `mul!`. Eg:
```julia
@♻ for i=1:5
    result = FuncOp₁ * 🔃(A * B)
end
```
will be transformed to 
```julia
🔃_1 = A * B
for i = 1:5
    result = FuncOp₁ * mul!(🔃_1, A, B)
end
```

 - **Lastly, assignments marked by `@🔃`:**
They will be transformed into a call of `mul!`. Of course, it works only if `@🔃` is directly followed by an assignment that has a single multiplication on the right side. Eg:
```julia
@♻ for i=1:5
    @🔃 result = FuncOp₁ * A
end
```
will be transformed to 
```julia
result = FuncOp₁ * A
for i = 1:5
    mul!(result, FuncOp₁, A)
end
```

Final note: `🔝` can be arbitrarily nested, and it can be embedded in expressions marked by `🔃`. `🔃` can also be nested, and it can be used in assigments marked by `@🔃` (along with `🔝`, of course).
"""
macro ♻(loop)
    🔝s = Array{Tuple{Symbol, Expr}}(undef, 0)
    🔃s = Array{Tuple{Symbol, Expr}}(undef, 0)
    counter = 0
    loop = MacroTools.postwalk(x -> begin
        if @capture(x, 🔝(expr_))
            newSymbol = Symbol(:🔝_, length(🔝s) + 1)
            push!(🔝s, (newSymbol, expr))           # preallocate an array before the loop
            newSymbol                              # replace the expression with name of buffer
        elseif @capture(x, 🔃(expr_))
            counter += 1
            newSymbol = Symbol(:🔃_, counter)
            push!(🔃s, (newSymbol, expr))          # preallocate an array before the loop
            @capture(expr, lhs_ * rhs_) ?          # replace the expression...
                :(mul!($newSymbol, $lhs, $rhs)) :  # ...with mul!, if it is multiplication;
                :(@.($newSymbol = $expr))          # ...with assignment + dot macro otherwise
        elseif @capture(x, @🔃 expr_)
            if @capture(expr, lhs_ = rhs1_ * rhs2_) || @capture(expr, lhs_ = mul!(e_, rhs1_, rhs2_))
                push!(🔃s, (lhs, :($rhs1 * $rhs2))) # preallocate an array before the loop
            elseif @capture(expr, lhs_ .= rhs1_ * rhs2_) || @capture(expr, lhs_ .= mul!(e_, rhs1_, rhs2_))
                # nothing to do here
            else
                @assert false "Macro @🔃 must be followed by an assigment that has a single multiplication on the right side"
            end
            :(mul!($lhs, $(rhs1), $(rhs2)))        # replace with mul!
        else
            x
        end
    end, loop)
    🔝_defs = [:($left = $right) for (left, right) in 🔝s]
    🔃_defs = [:($left = $right) for (left, right) in 🔃s]
    extended_loop = Expr(:block, 🔝_defs..., 🔃_defs..., loop)
    FO_settings.macro_verbose && println(MacroTools.prewalk(rmlines, extended_loop))
    esc(extended_loop)
end