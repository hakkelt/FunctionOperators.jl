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

# Equality check based on name
# HEADS UP! This works only when operators with the same name has also the same functionality!
Base.:(==)(FM1::FunctionOperatorComposite, FM2::FunctionOperatorComposite) =
    FM1.name == FM2.name

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
This transformation first allocates an array named `🔃_1`, and then in every iteration it is recalculated, saved to `🔃_1`, and the this value is used for the rest of the operation (i.e.: `FuncOp₁ * 🔃_1`. Note that `@.` macro is inserted before the inline assignment. This is needed otherwise `A + B` would allocate a new array before it is stored in `🔃_1`. **Warning!** It can break your code, e.g. @.(🔃_1 = A * B) ≠ (🔃_1 = A * B) {matrix multiplication vs. elementwise multiplication}! On the other hand, when the marked expression consists only a multiplication, then it is transformed into a call of `mul!`. Eg:
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
                if @capture(expr, lhs_ = rhs1_ * rhs2_)
                    push!(🔃s, (lhs, :($rhs1 * $rhs2))) # preallocate an array before the loop
                elseif @capture(expr, lhs_ .= rhs1_ * rhs2_)
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