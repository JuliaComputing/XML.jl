module XML

using Mmap

export
    Node, LazyNode,  # Core Types
    children, parent, nodetype, tag, attributes, value, depth, next, prev, # interface
    NodeConstructors  # convenience functions for creating Nodes

#-----------------------------------------------------------------------------# escape/unescape
# only used by Text nodes
const escape_chars = ('&' => "&amp;", '<' => "&lt;", '>' => "&gt;", "'" => "&apos;", '"' => "&quot;")
escape(x::AbstractString) = replace(x, escape_chars...)
unescape(x::AbstractString) = replace(x, reverse.(escape_chars)...)

#-----------------------------------------------------------------------------# NodeType
"""
    NodeType:
    - Document                  # prolog & root Element
    - DTD                       # <!DOCTYPE ...>
    - Declaration               # <?xml attributes... ?>
    - ProcessingInstruction    # <?NAME attributes... ?>
    - Comment                   # <!-- ... -->
    - CData                     # <![CData[...]]>
    - Element                   # <NAME attributes... > children... </NAME>
    - Text                      # text
"""
@enum(NodeType, CData, Comment, Declaration, Document, DTD, Element, ProcessingInstruction, Text)


#-----------------------------------------------------------------------------# raw
include("raw.jl")

abstract type AbstractXMLNode end

#-----------------------------------------------------------------------------# LazyNode
"""
    LazyNode(file::AbstractString)
    LazyNode(data::XML.Raw)

A Lazy representation of an XML node.
"""
mutable struct LazyNode <: AbstractXMLNode
    raw::Raw
    tag::Union{Nothing, String}
    attributes::Union{Nothing, Dict{String, String}}
    value::Union{Nothing, String}
end
LazyNode(raw::Raw) = LazyNode(raw, nothing, nothing, nothing)

function Base.getproperty(o::LazyNode, x::Symbol)
    x === :raw && return getfield(o, :raw)
    x === :nodetype && return nodetype(o.raw)
    x === :tag && return isnothing(getfield(o, x)) ? setfield!(o, x, tag(o.raw)) : getfield(o, x)
    x === :attributes && return isnothing(getfield(o, x)) ? setfield!(o, x, attributes(o.raw)) : getfield(o, x)
    x === :value && return isnothing(getfield(o, x)) ? setfield!(o, x, value(o.raw)) : getfield(o, x)
    x === :depth && return depth(o.raw)
    x === :children && return LazyNode.(children(o.raw))
    error("type LazyNode has no field $(x)")
end
Base.propertynames(o::LazyNode) = (:raw, :nodetype, :tag, :attributes, :value, :depth, :children)

Base.show(io::IO, o::LazyNode) = _show_node(io, o)

Base.read(io::IO, ::Type{LazyNode}) = LazyNode(read(io, Raw))
Base.read(filename::AbstractString, ::Type{LazyNode}) = LazyNode(read(filename, Raw))
Base.parse(x::AbstractString, ::Type{LazyNode}) = LazyNode(parse(x, Raw))

children(o::LazyNode) = LazyNode.(children(o.raw))
parent(o::LazyNode) = LazyNode(parent(o.raw))
depth(o::LazyNode) = depth(o.raw)

Base.IteratorSize(::Type{LazyNode}) = Base.SizeUnknown()
Base.eltype(::Type{LazyNode}) = LazyNode

function Base.iterate(o::LazyNode, state=o)
    n = next(state)
    return isnothing(n) ? nothing : (n, n)
end

function next(o::LazyNode)
    n = next(o.raw)
    isnothing(n) && return nothing
    n.type === RawElementClose ? next(LazyNode(n)) : LazyNode(n)
end
function prev(o::LazyNode)
    n = prev(o.raw)
    isnothing(n) && return nothing
    n.type === RawElementClose ? prev(LazyNode(n)) : LazyNode(n)
end

#-----------------------------------------------------------------------------# Node
"""
    Node(nodetype, tag, attributes, value, children)
    Node(node::Node; kw...)  # copy node with keyword overrides
    Node(node::LazyNode)  # un-lazy the LazyNode

A representation of an XML DOM node.  For convenience constructors, see the `XML.NodeConstructors` module.
"""
struct Node <: AbstractXMLNode
    nodetype::NodeType
    tag::Union{Nothing, String}
    attributes::Union{Nothing, Dict{String, String}}
    value::Union{Nothing, String}
    children::Union{Nothing, Vector{Node}}

    function Node(nodetype::NodeType, tag=nothing, attributes=nothing, value=nothing, children=nothing)
        new(nodetype,
            isnothing(tag) ? nothing : string(tag),
            isnothing(attributes) ? nothing : Dict(string(k) => string(v) for (k, v) in pairs(attributes)),
            isnothing(value) ? nothing : string(value),
            isnothing(children) ? nothing :
                children isa Vector{Node} ? children : begin
                    if any(x -> !(x isa Node), children)
                        Base.depwarn("Providing non-Node children to a Node is deprecated.  " *
                            "All provided children have been changed to Text(input)", :Node; force=true)
                    end
                    map(Node, collect(children))
                end
        )
    end
end
Node(o::Node; kw...) = isempty(kw) ? o : Node((get(kw, x, getfield(o, x)) for x in fieldnames(Node))...)

Node(data::Raw) = Node(LazyNode(data))

Node(x) = Node(Text, nothing, nothing, string(x), nothing)

function Node(node::LazyNode)
    (;nodetype, tag, attributes, value) = node
    c = XML.children(node)
    Node(nodetype, tag, attributes, value, isempty(c) ? nothing : map(Node, c))
end


Base.read(filename::AbstractString, ::Type{Node}) = Node(read(filename, Raw))
Base.read(io::IO, ::Type{Node}) = Node(read(io, Raw))
Base.parse(x::AbstractString, ::Type{Node} = Node) = Node(parse(x, Raw))

Base.setindex!(o::Node, val, i::Integer) = o.children[i] = Node(val)
Base.push!(a::Node, b::Node) = push!(a.children, b)

Base.show(io::IO, o::Node) = _show_node(io, o)

#-----------------------------------------------------------------------------# Node Constructors
function (T::NodeType)(args...; attr...)
    if T === Document
        !isempty(attr) && error("Document nodes do not have attributes.")
        Node(T, nothing, nothing, nothing, args)
    elseif T === DTD
        !isempty(attr) && error("DTD nodes only accept a value.")
        length(args) > 1 && error("DTD nodes only accept a value.")
        Node(T, nothing, nothing, only(args))
    elseif T === Declaration
        !isempty(args) && error("Declaration nodes only accept attributes")
        Node(T, nothing, attr)
    elseif T === ProcessingInstruction
        length(args) == 1 || error("ProcessingInstruction nodes require a tag and attributes.")
        Node(T, only(args), attr)
    elseif T === Comment
        !isempty(attr) && error("Comment nodes do not have attributes.")
        length(args) > 1 && error("Comment nodes only accept a single input.")
        Node(T, nothing, nothing, only(args))
    elseif T === CData
        !isempty(attr) && error("CData nodes do not have attributes.")
        length(args) > 1 && error("CData nodes only accept a single input.")
        Node(T, nothing, nothing, only(args))
    elseif T === Text
        !isempty(attr) && error("Text nodes do not have attributes.")
        length(args) > 1 && error("Text nodes only accept a single input.")
        Node(T, nothing, nothing, only(args))
    elseif T === Element
        tag = first(args)
        Node(T, tag, attr, nothing, args[2:end])
    else
        error("Unreachable reached while trying to create a Node via (::NodeType)(args...; kw...).")
    end
end

#-----------------------------------------------------------------------------# !!! common !!!
# Everything below here is common to all data structures


#-----------------------------------------------------------------------------# interface fallbacks
nodetype(o) = o.nodetype
tag(o) = o.tag
attributes(o) = o.attributes
value(o) = o.value
children(o::T) where {T} = isnothing(o.children) ? T[] : o.children

depth(o) = missing
parent(o) = missing
next(o) = missing
prev(o) = missing

nodeinfo(o) = (; nodetype=nodetype(o), tag=tag(o), attributes=attributes(o), value=value(o), depth=depth(o))


#-----------------------------------------------------------------------------# nodes_equal
function nodes_equal(a, b)
    out = XML.tag(a) == XML.tag(b)
    out &= XML.nodetype(a) == XML.nodetype(b)
    out &= XML.attributes(a) == XML.attributes(b)
    out &= XML.value(a) == XML.value(b)
    out &= length(XML.children(a)) == length(XML.children(b))
    out &= all(nodes_equal(ai, bi) for (ai,bi) in zip(XML.children(a), XML.children(b)))
    return out
end

Base.:(==)(a::AbstractXMLNode, b::AbstractXMLNode) = nodes_equal(a, b)

#-----------------------------------------------------------------------------# parse
Base.parse(::Type{T}, str::AbstractString) where {T} = parse(str, T)

#-----------------------------------------------------------------------------# indexing
Base.getindex(o::Union{Raw, AbstractXMLNode}) = o
Base.getindex(o::Union{Raw, AbstractXMLNode}, i::Integer) = children(o)[i]
Base.getindex(o::Union{Raw, AbstractXMLNode}, ::Colon) = children(o)
Base.lastindex(o::Union{Raw, AbstractXMLNode}) = lastindex(children(o))

Base.only(o::Union{Raw, AbstractXMLNode}) = only(children(o))

#-----------------------------------------------------------------------------# printing
function _show_node(io::IO, o)
    !ismissing(depth(o)) && print(io, depth(o), ':')
    printstyled(io, typeof(o), ' '; color=:light_black)
    printstyled(io, nodetype(o), ; color=:light_green)
    if o.nodetype === Text
        printstyled(io, ' ', repr(value(o)))
    elseif o.nodetype === Element
        printstyled(io, " <", tag(o), color=:light_cyan)
        _print_attrs(io, o)
        printstyled(io, '>', color=:light_cyan)
        _print_n_children(io, o)
    elseif o.nodetype === DTD
        printstyled(io, " <!DOCTYPE "; color=:light_cyan)
        printstyled(io, value(o), color=:light_black)
        printstyled(io, '>', color=:light_cyan)
    elseif o.nodetype === Declaration
        printstyled(io, " <?xml", color=:light_cyan)
        _print_attrs(io, o)
        printstyled(io, "?>", color=:light_cyan)
    elseif o.nodetype === ProcessingInstruction
        printstyled(io, " <?", tag(o), color=:light_cyan)
        _print_attrs(io, o)
        printstyled(io, "?>", color=:light_cyan)
    elseif o.nodetype === Comment
        printstyled(io, " <!--", color=:light_cyan)
        printstyled(io, value(o), color=:light_black)
        printstyled(io, "-->", color=:light_cyan)
    elseif o.nodetype === CData
        printstyled(io, " <![CData[", color=:light_cyan)
        printstyled(io, value(o), color=:light_black)
        printstyled(io, "]]>", color=:light_cyan)
    elseif o.nodetype === Document
        _print_n_children(io, o)
    elseif o.nodetype === UNKNOWN
        printstyled(io, "Unknown", color=:light_cyan)
        _print_n_children(io, o)
    else
        error("Unreachable reached")
    end
end

function _print_attrs(io::IO, o)
    x = attributes(o)
    !isnothing(x) && printstyled(io, [" $k=\"$v\"" for (k,v) in x]...; color=:light_yellow)
end
function _print_n_children(io::IO, o::Node)
    n = length(children(o))
    text = n == 0 ? "" : n == 1 ? " (1 child)" : " ($n children)"
    printstyled(io, text, color=:light_black)
end
_print_n_children(io::IO, o) = nothing

#-----------------------------------------------------------------------------# write_xml
write(x; kw...) = (io = IOBuffer(); write(io, x; kw...); String(take!(io)))

write(filename::AbstractString, x; kw...) = open(io -> write(io, x; kw...), filename, "w")

function write(io::IO, x; indent = "   ", depth=depth(x))
    nodetype = XML.nodetype(x)
    tag = XML.tag(x)
    value = XML.value(x)
    children = XML.children(x)
    depth = ismissing(depth) ? 1 : depth

    padding = indent ^ max(0, depth - 1)
    print(io, padding)
    if nodetype === Text
        print(io, escape(value))
    elseif nodetype === Element
        print(io, '<', tag)
        _print_attrs(io, x)
        print(io, isempty(children) ? '/' : "", '>')
        if !isempty(children)
            if length(children) == 1 && XML.nodetype(only(children)) === Text
                write(io, only(children); indent="")
                print(io, "</", tag, '>')
            else
                println(io)
                foreach(children) do child
                    write(io, child; indent)
                    println(io)
                end
                print(io, padding, "</", tag, '>')
            end
        end
    elseif nodetype === DTD
        print(io, "<!DOCTYPE", value, '>')
    elseif nodetype === Declaration
        print(io, "<?xml")
        _print_attrs(io, x)
        print(io, "?>")
    elseif nodetype === ProcessingInstruction
        print(io, "<?", tag)
        _print_attrs(io, x)
        print(io, "?>")
    elseif nodetype === Comment
        print(io, "<!--", value, "-->")
    elseif nodetype === CData
        print(io, "<![CData[", value, "]]>")
    elseif nodetype === Document
        foreach(children) do child
            write(io, child; indent)
            println(io)
        end
    else
        error("Unreachable case reached during XML.write")
    end
end

end
