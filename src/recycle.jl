# ----------------------------------------------------------
# -------------  @recycle optimization macro  -------------
# ----------------------------------------------------------

# Get all variable names from an expression
function getSymbols(expr)
    var_names = []
    MacroTools.postwalk(expr) do x
        #x isa Expr && [push!(var_names, s)
        #    for s in x.args[(x.head in (:call, :macrocall) ? 2 : 1):end] if s isa Symbol]
        x isa Symbol && Base.isidentifier(x) && push!(var_names, x)
        x
    end
    unique(var_names)
end

# Transform a number to subscript number (E.g.: 13 -> ₁₃)
toSubscript(num::Int64) = join([Char(0x2080 + parse(Int, d)) for d in split(string(num), "")])

function newExtractedFunOp(op, funops, extracted_ops)
    newSymbol = gensym("🔝$(toSubscript(length(extracted_ops)+1))")
    extracted_ops[newSymbol] = op
    push!(funops, newSymbol)
    newSymbol
end

# Receive a list of multiplication terms (sides), and replace all series of FunOps / any
# compatible types (numbers, scalings) with a unique identifier assigned to the replaced FunOp
# series before the optimized expression
# E.g.: Op₁ * Op₂ * array -> 🔝₁ = Op₁ * Op₂ (before the entire expression), 🔝₁ * array
# Replaced/extracted series cannot contain any variable modified inside the optimized expr
function extractFunOp(sides, funops, numbers, scalings, extracted_ops, modified)
    next_idx = 0
    new_sides = []
    temp = []
    for e in sides
        if (e in funops || e in numbers || e in scalings) && !(e in modified)
            push!(temp, e)
        else
            if length(temp) > 1 || length(temp) > 0 && temp[1] isa Expr
                op = length(temp) > 1 ? Expr(:call, :*, temp...) : temp[1]
                temp = [newExtractedFunOp(op, funops, extracted_ops)]
            end
            push!(new_sides, temp..., e)
            temp = []
        end
    end
    new_sides
end

# Get type of expressions and extract combined/adjoint operators applied to an array
# Eg: a * b is a number, if both a and b are numbers, but a * B is an array if B is array
# Eg: A * B * C -> A * B is extracted (and replaced by 🔝₁), if A, B are operators, and C is an array
function preprocess(expr_str, arrays, funops, numbers, scalings, extracted_ops, modified)
    MacroTools.postwalk(Meta.parse(expr_str)) do x
        if @capture(x, lhs_ + rhs__) || @capture(x, lhs_ .+ rhs__) ||
                @capture(x, lhs_ - rhs__) || @capture(x, lhs_ .- rhs__)
            any(e -> e in funops, [lhs, rhs...]) && !any(e -> e in modified, [lhs, rhs...]) &&
                return newExtractedFunOp(x, funops, extracted_ops)
            any(e -> e in arrays, [lhs, rhs...]) && push!(arrays, x)
            all(e -> e in numbers, [lhs, rhs...]) && push!(numbers, x)
        elseif @capture(x, lhs_ * rhs__)
            sides = [lhs, rhs...]
            if any(e -> e in arrays, sides)
                any(e -> e in funops, sides) && 
                    (sides = extractFunOp(sides, funops, numbers, scalings, extracted_ops, modified))
                push!(arrays, Expr(:call, :*, sides...))
                return Expr(:call, :*, sides...)
            elseif lhs in scalings && all(x -> x in numbers, rhs) ||
                    lhs in numbers && all(x -> x in scalings, rhs)
                push!(scalings, x)
            elseif all(e -> e in numbers, sides)
                push!(numbers, x)
            elseif any(e -> e in arrays, sides)
                push!(arrays, x)
            end
        elseif @capture(x, lhs_ .* rhs__)
            push!(arrays, x)
        elseif @capture(x, lhs_ / rhs_) || @capture(x, lhs_ ./ rhs_) ||
                @capture(x, lhs_ \ rhs_) || @capture(x, lhs_ .\ rhs_) ||
                @capture(x, lhs_ ÷ rhs_) || @capture(x, lhs_ .÷ rhs_) ||
                @capture(x, lhs_ % rhs_) || @capture(x, lhs_ .% rhs_) ||
                @capture(x, lhs_ ^ rhs_) || @capture(x, lhs_ .^ rhs_)
            any(e -> e in arrays, [lhs, rhs]) && push!(arrays, x)
            all(e -> e in numbers, [lhs, rhs]) && push!(numbers, x)
        elseif x isa Expr && x.head in (:(=), :+=, :-=, :*=, :/=, :\=, :÷=, :%=, :^=, :&=, :|=, :⊻=, :>>>=, :>>=, :<<=, :(.=), :.+=, :.-=, :.*=, :./=, :.\=, :.÷=, :.%=, :.^=, :.&=, :.|=, :.⊻=, :.>>>=, :.>>=, :.<<=)
            lhs, rhs = x.args
            push!(modified, lhs)
            rhs in funops && push!(funops, lhs)
            rhs in arrays && push!(arrays, lhs)
            rhs in numbers && push!(numbers, lhs)
            rhs in scalings && push!(scalings, lhs)
        elseif x isa Expr && string(x.head) == "'"                        # adjoint
            x.args[1] in funops && push!(funops, x)
            x.args[1] in arrays && push!(arrays, x)
        elseif x isa Expr && x.head == :call && x.args[1] in (:-, :+, :√) # unary operators
            x.args[2] in numbers && push!(numbers, x)
            x.args[2] in arrays && push!(arrays, x)
        elseif x isa Number
            push!(numbers, x)
        end
        x
    end
end

# Interestingly, a*b*c is parsed to *(a,b,c), but a.*b.*c is parsed to .*(.*(a,b),c),
# and, accordingly, .*(a,b,c) doesn't work.
# This function creates a correct expression from and operator and multiple terms
# E.g.: multiDot(:(.*), [a,b,c]) => .*(.*(a,b),c)
function multiDot(op, expr_list)
    length(expr_list) > 2 ?
        Expr(:call, op, multiDot(op, expr_list[1:end-1]), expr_list[end]) :
        Expr(:call, op, expr_list[1], expr_list[2])
end

# Attempts to replace +, -, *, and / operators with their respective "dot" operations
# whenever it is possible
function dotify(expr, arrays, numbers)
    MacroTools.postwalk(expr) do x
        if @capture(x, lhs_ + rhs__)
            if any(x -> x in arrays, [lhs, rhs...])
                new_expr = multiDot(:(.+), [lhs, rhs...])
                push!(arrays, new_expr)
                return new_expr
            end
        elseif @capture(x, lhs_ - rhs_)
            if lhs in arrays || rhs in arrays
                new_expr = :($lhs .- $rhs)
                push!(arrays, new_expr)
                return new_expr
            end
        elseif @capture(x, lhs_ / rhs_)
            if lhs in arrays && rhs in numbers || lhs in numbers && rhs in arrays
                new_expr = :($lhs ./ $rhs)
                push!(arrays, new_expr)
                return new_expr
            end
        elseif @capture(x, lhs_ * rhs__)
            terms = [lhs, rhs...]
            if any(x -> x in arrays, terms)
                left_last_number = 0
                for (i,e) in enumerate(terms)
                    e in numbers ? (left_last_number = i) : break
                end
                right_last_number = length(terms) + 1
                for (i,e) in enumerate(reverse(terms))
                    e in numbers ? (right_last_number = length(terms) - i + 1) : break
                end
                if left_last_number > 0 || right_last_number < length(terms) + 1
                    new_expr = left_last_number + 1 == right_last_number - 1 ||
                                    right_last_number == length(terms) ?
                        multiDot(:(.*), terms) :
                        multiDot(:(.*), vcat(terms[1:left_last_number],
                            Expr(:call, :*, terms[left_last_number+1:right_last_number-1]...),
                            terms[right_last_number:end]))
                    push!(arrays, new_expr)
                    return new_expr
                end
            end
        end
        return x
    end
end

# Tell if the given expression's top level operation is a "dot" operation
# E.g.: a .+ (b * c) => true, a + (b .* c) => false
isDotExpr(expr) = expr isa Expr && expr.head == :call &&
    (startswith(string(expr.args[1]), ".") || endswith(string(expr.args[1]), "."))

# Create a new identifier for a buffer and "register" it (i.e. add to "buffers" list,
# so it will be initialized to nothing before the entire expression)
function newTempBuffer(buffers)
    newSymbol = gensym("🔃$(toSubscript(length(buffers)+1))")
    push!(buffers, newSymbol)
    newSymbol
end

# Just to make sure that my helper function calls doesn't conflict with functions
# created by the user. Actually, these function that are formally called are no functions at all,
# but rather they are used to mark to spots where further replacements needed later
const ifFirstEqual = gensym("ifFirstEqual")
const ifFirstMult = gensym("ifFirstMult")

# Add a buffer to store the result of a "dot" expression, if applicable
# E.g.: A .+ (B * C) -> ifFirstEqual(🔃ₓ, A .+ (B * C), :(=), :(.=))
#   which will be later (in postprocess function) transformed to:
# if is_first_runₓ
#    is_first_runₓ
#    ...
#    🔃ₓ = A .+ (B * C)
#    ...
# else
#    ...
#    🔃ₓ .= A .+ (B * C)
#    ...
# end
# ...🔃ₓ...
function bufferIfDotExpr(expr, buffers)
    if isDotExpr(expr)
        buffer = newTempBuffer(buffers)
        push!(buffers, buffer)
        Expr(:call, ifFirstEqual, buffer, expr, :(=), :(.=))
    else
        expr
    end
end

# Try to add a buffer to store result of "dot" expressions, and replace array-array and funop-array
# multiplications with a call to mul!, and also add a buffer to store result of mul!
function buffer(expr, arrays, array_symbols, funops, buffers)
    # Capture the expressions where buffer is already given (i.e., as left side of assignment)
    # E.g.: A = B * C -> is_first_run ? A = B * C : mul!(A, B, C)
    expr = MacroTools.prewalk(expr) do x
        if x isa Expr && x.head in (:(=), :+=, :-=, :*=, :/=, :(.=), :.+=, :.-=, :.*=, :./=)
            lhs, rhs = x.args[1], x.args[2]
            if isDotExpr(x.args[2])
                dotOp = Symbol(".", x.head)
                if !(lhs in array_symbols)
                    push!(buffers, lhs)
                    Expr(:call, ifFirstEqual, lhs, rhs, x.head, dotOp)
                else
                    Expr(dotOp, lhs, rhs)
                end
            elseif @capture(rhs, rhs1_ * rhs2_) && any(x -> x in arrays, [lhs, rhs1, rhs2])
                if lhs in array_symbols # if lhs is already assigned
                    :(mul!($lhs, $rhs1, $rhs2))
                else
                    Expr(:call, ifFirstMult, lhs, rhs1, rhs2)
                end
            elseif @capture(rhs, rhs1_ * rhs2__) && (rhs1 in arrays || any(x -> x in arrays, rhs2))
                if lhs in array_symbols # if lhs is already assigned
                    Expr(:call, :mul!, lhs, rhs1, Expr(:call, :*, rhs2...))
                else
                    Expr(:call, ifFirstMult, lhs, rhs1, Expr(:call, :*, rhs2...))
                end
            else
                x
            end
        else
            x
        end
    end
    # Capture all other possible cases
    # ("dot" expressions, and array-array, funop-array multiplications)
    MacroTools.postwalk(expr) do x
        if @capture(x, rhs1_ * rhs2_) && (rhs1 in arrays || rhs2 in arrays)
            lhs = newTempBuffer(buffers)
            rhs1, rhs2 = bufferIfDotExpr(rhs1, buffers), bufferIfDotExpr(rhs2, buffers)
            Expr(:call, ifFirstMult, lhs, rhs1, rhs2)
        elseif @capture(x, rhs1_ * rhs2__) && (rhs1 in arrays || any(x -> x in arrays, rhs2))
            lhs = newTempBuffer(buffers)
            rhs1 = bufferIfDotExpr(rhs1, buffers)
            rhs2 = map(x -> bufferIfDotExpr(x, buffers), rhs2)
            Expr(:call, ifFirstMult, lhs, rhs1, Expr(:call, :*, rhs2...))
        elseif x isa Expr && x.head == :call && x.args[1] != ifFirstEqual &&
                !(startswith(string(x.args[1]), ".") || endswith(string(x.args[1]), "."))
            Expr(:call, x.args[1], map(x -> bufferIfDotExpr(x, buffers), x.args[2:end])...)
        else
            x
        end
    end
end

# Create a new identifier for a bool variable and "register" it (i.e. add to "first_bools" list,
# so it will be initialized to true before the entire expression)
function newFirstBool(first_bools)
    newSymbol = gensym("is_first_run$(toSubscript(length(first_bools)+1))")
    push!(first_bools, newSymbol)
    newSymbol
end

# Create an if-expression that holds all calculations of intermediate values for a given line
# For example:
# if is_first_runₓ
#    is_first_runₓ
#    ...
#    🔃ₓ = A .+ (B * C)
#    ...
# else
#    ...
#    🔃ₓ .= A .+ (B * C)
#    ...
# end
function createIfBlock(x, first, second, first_bools)
    first_bool = newFirstBool(first_bools)
    if_block = Expr(:if, first_bool,
        Expr(:block, :($first_bool = false), first...), Expr(:block, second...))
    if x isa Expr && x.head == :macrocall && length(x.args) == 3
        x.args[3] isa Symbol ?
            Expr(:macrocall, x.args[1], x.args[2], if_block) :
            Expr(:macrocall, x.args[1], x.args[2], Expr(:block, if_block, x.args[3]))
    elseif x isa Expr
        Expr(:block, if_block, x)
    else
        if_block
    end
end

# Remove virtual calls to ifFirstEqual and ifFirstMult "functions", and add the respective if-block
function postprocess(expr, first_bools)
    # Dicts holding intermediate calculations
    first, otherwise = Dict(), Dict() # key: line number, value: expressions
    current_line = 0
    # Just gather all intermediate calculations (for both first and later runs)
    expr = MacroTools.postwalk(expr) do x
        if @capture(x, fun_name_(lhs_, rhs_, op_, dotOp_)) && fun_name == ifFirstEqual
            push!(get!(first, current_line, []), Expr(op, lhs, rhs))
            push!(get!(otherwise, current_line, []), Expr(dotOp, lhs, rhs))
            x = lhs
        elseif @capture(x, fun_name_(lhs_, rhs1_, rhs2_)) && fun_name == ifFirstMult
            push!(get!(first, current_line, []),
                Expr(:(=), lhs, Expr(:call, :*, rhs1, rhs2)))
            push!(get!(otherwise, current_line, []),
                Expr(:call, :mul!, lhs, rhs1, rhs2))
            x = lhs
        end
        if x isa LineNumberNode
            current_line = x.line
        end
        x
    end
    current_line_changed = current_line == 0
    # Create if-blocks from gathered intermediate calculations
    expr = MacroTools.prewalk(expr) do x
        if x isa LineNumberNode && current_line != x.line
            current_line = x.line
            current_line_changed = true
            x
        elseif current_line_changed && # top level = we see an entire line
                current_line in keys(first) && length(first[current_line]) > 0
            current_line_changed = false
            createIfBlock(x, first[current_line], otherwise[current_line], first_bools)
        else
            x
        end
    end
    # Expand blocks nested directly in other blocks
    # E.g:
    # begin
    #     a = 3
    #     begin
    #         b = 4
    #         c = 7
    #     end
    # end
    # ...transformed to
    # begin
    #     a = 3
    #     b = 4
    #     c = 7
    # end
    MacroTools.postwalk(expr) do x
        if x isa Expr && x.head == :block
            new_block_content = []
            for item in x.args
                if item isa Expr && item.head == :block
                    for item2 in item.args
                        push!(new_block_content, item2)
                    end
                else
                    push!(new_block_content, item)
                end
            end
            Expr(:block, new_block_content...)
        else
            x
        end
    end
end

# It is not a necessary function, but might help user to debug transformed code
# Add line numbers matching the lines of transformed code (the call stack will be more 
# informative then if an error occures inside the transformed code)
function addLineNumbers(expr)
    # Remove previous line numbers and add correct ones instead
    result = Meta.parse(string(MacroTools.striplines(expr)))
    # fix LineNumberNodes to be more informative
    MacroTools.postwalk(result) do x
        x isa LineNumberNode ?
            LineNumberNode(x.line, Symbol("generated_code_by_recycle")) :
            x
    end
end

# Replace gensyms with their names and add line numbers in the beginning of each line
function prettify(expr)
    expr = MacroTools.postwalk(
        x -> MacroTools.isgensym(x) ? Symbol(MacroTools.gensymname(x)) : x, expr)
    txt = string(MacroTools.striplines(expr))
    lines = split(txt, "\n")
    lines_with_numbers = [@sprintf("\n%3d | %s", i, line) for (i, line) in enumerate(lines)]
    join(lines_with_numbers)
end

# This function basicly does the entire job by calling all functions above
function transform(expr_str, arrays, funops, numbers, scalings)
    array_symbols = copy(arrays)
    extracted_ops, buffers, modified, first_bools = Dict(), [], [], []
    # Optimize by replacements
    result = preprocess(expr_str, arrays, funops, numbers, scalings, extracted_ops, modified) |>
        x -> dotify(x, arrays, numbers) |>
        x -> buffer(x, arrays, array_symbols, funops, buffers) |>
        x -> postprocess(x, first_bools)
    # Add initialization of extracted operaors, buffers and "first bool"s
    init_🔝 = length(extracted_ops) > 0 ?
        [Expr(:(=), l, r) for (l,r) in sort(collect(extracted_ops), by=x->x[1])] : []
    init_🔃 = Expr(:(=), Expr(:tuple, buffers...), Expr(:call, :fill, :nothing, length(buffers)))
    init_first_bools =
            Expr(:(=), Expr(:tuple, first_bools...), Expr(:call, :fill, :true, length(first_bools)))
    result = length(buffers) > 0 ? 
        Expr(:block, init_🔝..., init_🔃, init_first_bools, result) : Expr(:block, init_🔝..., result)
    # Self-explanatory...
    result = addLineNumbers(result)
    # Wrap it in a try-catch block to print the generated code before the error message is rethrown
    extended = Expr(:try, result, :e,
        Expr(:block,
            Expr(:call, :println, "\ngenerated_code_by_recycle:", prettify(result)),
            :(rethrow(e))))
    # return...
    result, extended, modified
end

macro string_varname_assign(str,val)
    s = Symbol(str)
    esc(:($s = $val))
end

"""
Speed up iteratively executed code fragments with many matrix operations by transforming code in such a way that preserves arrays allocated for intermediate results, and re-use them for subsequent iterations.

First variant:
```julia
@recycle <code to be optimized>
```
Second variant:
```julia
@recycle(arrays = [<list of array variables>], funops = [<list of funop variables], numbers = [<list of number variables>], <code to be optimized>)
```

The **first variant** is the more convenient one that tries to guess the type of variables (the other variant requires its user to declare explicitly the list of variables which are type of Array, FunOp, and Number. As a tradeoff, this variant fails when the optimized code contains either a closure or non-const global variable.

The **second variant** is the more flexible (and also more verbose) one one that requires its user to declare explicitly the list of variables which are type of Array, FunOp, and Number. The other variant tries to guess the type of variables, thus it is more convenient, but as a tradeoff, that variant fails when the optimized code contains either a closure or non-const global variable. On the other hand, this (more verbose) variant is free from these limitations.
*Note: All of the "keyword arguments" are optional, and also their order is arbitrary.*

An example to first variant:
This function
```julia
function foo()
    A = rand(100,100)
    B = rand(100,100)
    @recycle for i = 1:5
        A += A / 2 + B
        C = A * B + 5
    end
end
```
is turned into the following:
```julia
function foo()
    A = rand(100,100)
    B = rand(100,100)
    (C, 🔃₂) = fill(nothing, 2)
    (is_first_run₁,) = fill(true, 1)
    for i = 1:5
        A .+= A ./ 2 .+ B
        if is_first_run₁
            is_first_run₁ = false
            🔃₂ = A * B
            C = 🔃₂ .+ 5
        else
            mul!(🔃₂, A, B)
            C .= 🔃₂ .+ 5
        end
    end
end
```

Another example showing what second variant can do (and the first can't):
```julia
bar = @recycle(arrays=[A,B], (A, B) -> begin
    A += A / 2 + B
    B = A * B .+ 5
end)
function baz()
    A = rand(100,100)
    B = rand(100,100)
    for i = 1:5
        bar(A,B)
    end
end
```
is turned into the following:
```julia
bar = begin
    (🔃₁,) = fill(nothing, 1)
    (is_first_run₁,) = fill(true, 1)
    (A, B)->begin
            A .+= A ./ 2 .+ B
            begin
                if is_first_run₁
                    is_first_run₁ = false
                    🔃₁ = A * B
                else
                    mul!(🔃₁, A, B)
                end
                B .= 🔃₁ .+ 5
            end
        end
end
function baz()
    A = rand(100,100)
    B = rand(100,100)
    for i = 1:5
        bar(A,B)
    end
end
```
"""
macro recycle(expr)
    generated_func_name = Symbol("recycle_function_@",__source__.file, "_", __source__.line)
    vars = getSymbols(expr)
    !(:mul! in vars) && push!(vars, :mul!)
    build_array_of_array_varnames =
        [:($var <: AbstractArray && push!(arrays, Symbol($(string(var))))) for var in vars]
    build_array_of_FunOp_varnames =
        [:($var <: FunOp && push!(funops, Symbol($(string(var))))) for var in vars]
    build_array_of_Number_varnames =
        [:($var <: Number && push!(numbers, Symbol($(string(var))))) for var in vars]
    build_array_of_outer_vars =  # Variables defined outside of the optimized code
        [:(push!(variables, $var <: Nothing ? nothing : Symbol($(string(var))))) for var in vars]
    expr_str = string(expr)
    print_vars = [:(Core.println($(Expr(:., :Main, var)))) for var in vars]
    eval(quote
        @generated function $generated_func_name($(vars...))
            arrays, funops, numbers, variables = [], [], [], []
            # Get type of atoms (symbols)
            $(build_array_of_array_varnames...)
            $(build_array_of_FunOp_varnames...)
            $(build_array_of_Number_varnames...)
            $(build_array_of_outer_vars...)
            quote
                @recycle(arrays=[$((arrays)...)], funops=[$((funops)...)], numbers=[$((numbers)...)], variables=[$((variables)...)], $$expr_str)
            end
        end
    end)
    if_params = [Expr(:if, Expr(:isdefined, var), var, nothing) for var in vars]
    var_names = map(var -> string(var), vars)
    new_values = gensym("new_values")
    assign_list = [:($var_name in keys($new_values) && 
        FunctionOperators.@string_varname_assign $var_name $new_values[$var_name])
            for var_name in var_names if !isconst(Main, Symbol(var_name))]
    esc(quote
        $new_values = FunctionOperators.$generated_func_name( $(if_params...) )
        $(assign_list...)
        $new_values["##@recycle return value##"]
    end)
end

macro recycle(args...)
    arrays, funops, numbers, variables = [], [], [], []
    expr = nothing
    for a in args
        if a isa Expr && a.head == :(=)
            @assert a isa Expr "All keywords arguments of @recycle must be an expression"
            if a.args[1] == :arrays
                @assert a.args[2].head == :vect "Parameter \"arrays\" must be a list of arrays variables"
                arrays = a.args[2].args
            elseif a.args[1] == :funops
                @assert a.args[2].head == :vect "Parameter \"funops\" must be a list of arrays variables"
                funops = a.args[2].args
            elseif a.args[1] == :numbers
                @assert a.args[2].head == :vect "Parameter \"numbers\" must be a list of arrays variables"
                numbers = a.args[2].args
            elseif a.args[1] == :variables
                @assert a.args[2].head == :vect "Parameter \"variables\" must be a list of arrays variables"
                variables = a.args[2].args
            else
                @assert false "Unrecognized keyword argument: $(a.args[1])"
            end
        else
            @assert a isa Expr || a isa String "@recycle must receive the expression to be optimized as an expression or a string"
            @assert expr == nothing "@recycle can accept only one positional argument (the expression to be optimized)"
            expr = a
        end
    end
    scalings = @isdefined(I) && I isa UniformScaling ? [I] : []
    expr_str = expr isa String ? expr : string(expr)
    result, extended, modified = transform(expr_str, arrays, funops, numbers, scalings)
    FunctionOperators_global_settings.macro_verbose && Core.println(prettify(result))
    if length(variables) > 0
        to_be_returned = intersect(modified, variables)
        return_pairs = [Expr(:call, :(=>), string(var), var) for var in to_be_returned]
        return_val = gensym("return_val")
        push!(return_pairs, Expr(:call, :(=>), "##@recycle return value##", return_val))
        return_dict = Expr(:call, :Dict, return_pairs...)
        extended.args[1] = Expr(:block, Expr(:(=), return_val, result), return_dict)
    end
    esc(extended)
end