# ----------------------------------------------------------
# -------------- The real magic happens here ---------------
# ----------------------------------------------------------
# --- Allocate buffers for operator outputs ----------------
# ------------------- and create the aggragated function ---
# ----------------------------------------------------------

# This WeakKeyDict stores all already allocated buffers. It serves like a "L2-cache": when newBuffer
# function cannot find a proper buffer in storage ("L1-cache"), then it tries to find one in bufferPool.
# And as it is a WeakKeyDict, it allows Garbage Collector to release buffers not used any more.
const bufferPool = Array{WeakKeyDict{Buffer, Int}, 1}(undef, 0)

const bufferCounter = Counter(Threads.Atomic{Int}(1))
getNextBufferNum() = Threads.atomic_add!(bufferCounter.num, 1)

# Special constructor of Buffer type
# We get the list of all previously allocated buffers (storage) and first we try to find
# there a buffer with appropriate size which is also marked as available.
# If we find a good one, we don't allocate a new one.
function newBuffer(datatype::Type, new_size::Tuple{Vararg{Int}}, storage::Vector{Buffer})
    for i in range(length(storage), stop=1, step=-1)
        if length(storage[i].buffer) == prod(new_size) && eltype(storage[i].buffer) == datatype && storage[i].available
            return size(storage[i].buffer) == new_size ?
                storage[i] :
                Buffer(reshape(storage[i].buffer, new_size), storage[i].name, storage[i].number, true)
        end
    end
    new_buffer = nothing
    for (buffer, bufferLength) in bufferPool[Threads.threadid()]
        if bufferLength == prod(new_size) && eltype(buffer.buffer) == datatype && buffer.available
            new_buffer = size(buffer.buffer) == new_size ?
                buffer :
                Buffer(reshape(buffer.buffer, new_size), buffer.name, buffer.number, true)
            info("Re-using $(buffer.number) from bufferPool")
            break
        end
    end
    if new_buffer isa Nothing
        number = getNextBufferNum()
        name = "buffer"*string(number)
        info("Allocation of $name, size: $(new_size)")
        new_buffer = Buffer(Array{datatype}(undef, new_size), name, number, true)
        push!(bufferPool[Threads.threadid()], new_buffer => length(new_buffer.buffer))
    end
    push!(storage, new_buffer)
    new_buffer
end

#  --- getPlan functions ---
# Traverse the computational tree recursively, and tries to allocate as few buffer
# as it is (safely) possible. The goal is to get three values:
#   - A function that accepts a buffer and an input vector, it has identical functionality
#        as the operation defined by the node, and it stores the result in the given buffer
#   - A buffer which is capable of store the output of operation
#   - A string representation of the function created
#
# How is the function created that aggregates the functionality of combined operators?
# When processing a node in the computational tree, we create a new function that invokes the children nodes' aggregated functions. Trivially, it means "x -> OP1.forw(OP2.forw(x))" in case of "OP1 * OP2", and "x -> OP1.forw(x) + OP2.forw(x)" in case of "OP1 + OP2". If the node is marked as adjoint, then roles of right and left nodes are switched and it toggles their adjoint flag by xor operation (⊻); but adjoint of addition/substraction cannot by calculated that way, so an error message is thrown.
#
# How the buffers are handled?
# The buffers and passed up and down in the computational tree. Buffers descending in the tree are always the ones that are capable to store the value of output of the parent node. If it also fits the requirents of the children nodes, then the children nodes will use it to store their intermediate results. If they can't use it, they allocate their own buffers to store their intermediate results. There are three main cases:
#  - In case of multiplication of operators, the parent node passes down the buffer received from above to its right children node initiating the traversion of right node. When the traversion of right node is done, the parent receives a buffer from the right node, which will hold the output value of right node operation. Then the parent node passes the same buffer to the left node, which was previously passed to the right node, and initiates the traversion of left node. If any of the children node return buffer different from the one they received, then that buffer will be captured in the closure.
#  - In case of addition/substraction of operators, the parent allocates first a buffer for its input (to avoid calculating it two times by left and right children), and then initiates the traversal of left node. The buffer returned from the left node might be used by the right node, if exactly one of left and right is mutating, otherwise the result of left node would be overwritten by the right node before the addition. Then the closures are created accordingly. (One additional trick: if the left is mutating, but the right is not, then they are switched.)
#  - In case of leaf is reached, allocates a new buffer, if the size of the received one doesn't fit its requirements, otherwise use the provided one.

# "In case of multiplication of operators..."
function getPlanMul(FO::FunctionOperatorComposite, buffer::Buffer, adjoint::Bool, inside::String,
        storage::Vector{Buffer})
    left, right = adjoint ? (FO.right, FO.left) : (FO.left, FO.right)
    rFunc, rBuffer, rText = getPlan(right, buffer, adjoint ⊻ right.adjoint, inside, storage)
    lFunc, lBuffer, lText = getPlan(left, buffer, adjoint ⊻ left.adjoint, rText, storage)
    if rBuffer.name == buffer.name == lBuffer.name
        (buffer, x) -> lFunc(buffer, rFunc(buffer, x)), lBuffer, lText
    elseif lBuffer.name == buffer.name != rBuffer.name
        (buffer, x) -> lFunc(buffer, rFunc(rBuffer.buffer, x)), lBuffer, lText
    #elseif lBuffer.name != buffer.name == rBuffer.name
        # This case never happens
        #((buffer, x) -> lFunc(lBuffer.buffer, rFunc(buffer, x)), lBuffer, lText)
    else
        (buffer, x) -> lFunc(lBuffer.buffer, rFunc(rBuffer.buffer, x)), lBuffer, lText
    end
end

# Some code generation macro to avoid repetitive code in getPlanAddSub
macro createReturnValue(left, right, op)
    lBuf = left == :buffer ? :buffer : :(lBuffer.buffer)
    rBuf = right == :buffer ? :buffer : :(rBuffer.buffer)
    name = left == :buffer ? :(buffer.name) : :(lBuffer.name)
    esc(quote
        #if FO.left.ismutating && !FO.right.ismutating
        #   if $op == +
        #       ((buffer, x) -> begin
        #            inBuff.buffer .= x;
        #            broadcast!(+, $lBuf, rFunc($rBuf, inBuff.buffer), lFunc($lBuf, inBuff.buffer))
        #        end, lBuffer, "($(inBuff.name) .= $inside; broadcast!(+, $($name), $rText, $lText))")
        #    else
        #       ((buffer, x) -> begin
        #            inBuff.buffer .= x;
        #            broadcast!((x,y) -> y-x, $lBuf, rFunc($rBuf, inBuff.buffer), lFunc($lBuf, inBuff.buffer))
        #       end, lBuffer, "($(inBuff.name) .= $inside; broadcast!((x,y) -> y-x, , $($name), $rText, $lText))")
        #    end
        #else
           ((buffer, x) -> begin
                inBuff.buffer .= x;
                broadcast!($op, $lBuf, lFunc($lBuf, inBuff.buffer), rFunc($rBuf, inBuff.buffer))
            end, lBuffer, "($(inBuff.name) .= $inside; broadcast!($op, $($name), $lText, $rText))")
        #end
    end)
end

# "In case of addition/substraction of operators..."
function getPlanAddSub(FO::FunctionOperatorComposite, buffer::Buffer, adjoint::Bool, inside::String,
        op::Symbol, storage::Vector{Buffer})
    adjoint && error("Sorry, I don't know how to calculate the adjoint of $(FO.name)")
    buffer.available = false
    inBuff = newBuffer(eltype(FO), FO.inDims, storage)
    inBuff.available = false
    lFunc, lBuffer, lText = getPlan(FO.left, buffer, adjoint ⊻ FO.left.adjoint, inBuff.name, storage)
    lBuffer.available = false
    inBuff.available = true
    rBuffer = #FO.left.ismutating && FO.right.ismutating ? 
        newBuffer(eltype(FO), FO.outDims, storage) #: lBuffer
    rFunc, rBuffer, rText = getPlan(FO.right, rBuffer, adjoint ⊻ FO.right.adjoint, inBuff.name, storage)
    lBuffer.available = buffer.available = true
    if rBuffer.name == buffer.name == lBuffer.name
        op == :+ ? @createReturnValue(buffer, buffer, +) : @createReturnValue(buffer, buffer, -)
    elseif lBuffer.name == buffer.name != rBuffer.name
        op == :+ ? @createReturnValue(buffer, rBuffer, +) : @createReturnValue(buffer, rBuffer, -)
    #elseif lBuffer.name != buffer.name == rBuffer.name
        # This case never happens
        #op == :+ ? @createReturnValue(lBuffer, buffer, +) : @createReturnValue(lBuffer, buffer, -)
    else
        op == :+ ? @createReturnValue(lBuffer, rBuffer, +) : @createReturnValue(lBuffer, rBuffer, -)
    end
end

# Pretty much self-explanatory...
function getPlan(FO::FunctionOperatorComposite, buffer::Buffer, adjoint::Bool, inside::String,
        storage::Vector{Buffer})
    if FO.operator == :*
        getPlanMul(FO, buffer, adjoint, inside, storage)
    elseif FO.operator in (:+, :-)
        getPlanAddSub(FO, buffer, adjoint, inside, FO.operator, storage)
    else
        error("Unknown operator: $(FO.operator)")
    end
end

# "In case of leaf is reached..."
function getPlan(FO::FunctionOperator, buffer::Buffer, adjoint::Bool, inside::String,
        storage::Array{Buffer,1})
    # We need to check "adjoint != FO.adjoint" because adjoint operation propagates downward in the computation tree.
    # Adjoint symbol switches inDims and outDims of the top-level
    # FunctionOperatorComposite object, but leaves intact its descendants.
    # Thus, sometimes inDims and outDims are already switched, but sometimes not,
    # that's why we need this awkward expression: adjoint != FO.adjoint ? FO.inDims : FO.outDims
    (inDims, outDims) = adjoint != FO.adjoint ? (FO.outDims, FO.inDims) : (FO.inDims, FO.outDims)
    size(buffer.buffer) != outDims && (buffer = newBuffer(eltype(FO), outDims, storage))
    if checkTwoInputs(FO.forw)
        text = FO.scaling ?
            "broadcast!(*, $(buffer.name), $(adjoint ? conj(FO.getScale()) : FO.getScale()), $inside)" : 
            FO.name*(adjoint ? ".backw" : ".forw")*"($(buffer.name), $inside)"
        (adjoint ? (b,x) -> begin FO.backw(b,x); b; end : (b,x) -> begin FO.forw(b,x); b; end, buffer, text)
    else
        text = buffer.name*" .= "*FO.name*(adjoint ? ".backw" : ".forw")*"($inside)"
        (adjoint ?
            (b, x) -> b .= reshape(FO.backw(x), size(b)) :
            (b, x) -> b .= reshape(FO.forw(x), size(b)),
        buffer, text)
    end
end