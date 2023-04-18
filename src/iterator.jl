struct Node2
    nodetype::NodeType
    tag::Union{Nothing, Symbol}
    attributes::Union{Nothing, Dict{Symbol, String}}
end



#-----------------------------------------------------------------------------# XMLIterator
struct XMLIterator{T}
    io::T
end
