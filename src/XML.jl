module XML

using Mmap

export
    Node, LazyNode,  # Core Types
    children, parent, nodetype, tag, attributes, value, depth, next, prev, # interface
    NodeConstructors  # convenience functions for creating Nodes

#-----------------------------------------------------------------------------# escape/unescape
# only used by TEXT nodes
const escape_chars = ('&' => "&amp;", '<' => "&lt;", '>' => "&gt;", "'" => "&apos;", '"' => "&quot;")
escape(x::AbstractString) = replace(x, escape_chars...)
unescape(x::AbstractString) = replace(x, reverse.(escape_chars)...)

#-----------------------------------------------------------------------------# NodeType
"""
    NodeType:
    - DOCUMENT                  # prolog & root ELEMENT
    - DTD                       # <!DOCTYPE ...>
    - DECLARATION               # <?xml attributes... ?>
    - PROCESSING_INSTRUCTION    # <?NAME attributes... ?>
    - COMMENT                   # <!-- ... -->
    - CDATA                     # <![CDATA[...]]>
    - ELEMENT                   # <NAME attributes... > children... </NAME>
    - TEXT                      # text
"""
@enum(NodeType, DOCUMENT, DTD, DECLARATION, PROCESSING_INSTRUCTION, COMMENT, CDATA, ELEMENT, TEXT)

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

LazyNode(file::AbstractString) = LazyNode(Raw(file))

parse(x::AbstractString, ::Type{LazyNode}) = LazyNode(parse(x, Raw))

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
    n.type === RAW_ELEMENT_CLOSE ? next(LazyNode(n)) : LazyNode(n)
end
function prev(o::LazyNode)
    n = prev(o.raw)
    isnothing(n) && return nothing
    n.type === RAW_ELEMENT_CLOSE ? prev(LazyNode(n)) : LazyNode(n)
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
    function Node(nodetype, tag=nothing, attributes=nothing, value=nothing, children=nothing)
        new(nodetype, tag, attributes, value, children)
    end
end
Node(o::Node) = o

Node(o::Node; kw...) = Node((get(kw, x, getfield(o, x)) for x in fieldnames(Node))...)

Node(file::AbstractString) = Node(Raw(file))

Node(data::Raw) = Node(LazyNode(data))

function Node(node::LazyNode)
    (;nodetype, tag, attributes, value) = node
    c = XML.children(node)
    Node(nodetype, tag, attributes, value, isempty(c) ? nothing : map(Node, c))
end

parse(x::AbstractString, ::Type{Node} = Node) = Node(parse(x, Raw))

Base.setindex!(o::Node, val, i::Integer) = o.children[i] = Node(val)
Base.push!(a::Node, b::Node) = push!(a.children, b)

Base.show(io::IO, o::Node) = _show_node(io, o)

#-----------------------------------------------------------------------------# Node Constructors
# auto-detect how to create a Node
_node(x; depth=-1) = Node(nodetype=TEXT, value=string(x); depth)
_node(x::Node; depth=x.depth) = Node(x; depth)

module NodeConstructors
import .._node
import ..Node, ..Dict
import ..TEXT, ..DOCUMENT, ..DTD, ..DECLARATION, ..PROCESSING_INSTRUCTION, ..COMMENT, ..CDATA, ..ELEMENT

export document, dtd, declaration, processing_instruction, comment, cdata, text, element

attrs(kw) = Dict{String,String}(string(k) => string(v) for (k,v) in kw)

"""
    document(children::Vector{Node})
    document(children::Node...)

Create an `XML.Node` with `nodetype=DOCUMENT` and the provided `children`.
"""
document(children::Vector{Node}) = Node(DOCUMENT, nothing, nothing, nothing, children)
document(children::Node...) = document(collect(children))

"""
    dtd(value::AbstractString)

Create an `XML.Node` with `nodetype=DTD` and the provided `value`.
"""
dtd(value::AbstractString) = Node(DTD, nothing, nothing, String(value))

"""
    declaration(; attributes...)

Create an `XML.Node` with `nodetype=DECLARATION` and the provided `attributes`.
"""
declaration(attributes::Dict{String,String}) = Node(DECLARATION, nothing, attributes)
declaration(; kw...) = declaration(attrs(kw))

"""
    processing_instruction(tag::AbstractString; attributes...)

Create an `XML.Node` with `nodetype=PROCESSING_INSTRUCTION` and the provided `tag` and `attributes`.
"""
processing_instruction(tag, attributes::Dict{String,String}) = Node(PROCESSING_INSTRUCTION, string(tag), attributes)
processing_instruction(tag; kw...) = processing_instruction(tag, attrs(kw))

"""
    comment(value::AbstractString)

Create an `XML.Node` with `nodetype=COMMENT` and the provided `value`.
"""
comment(value::AbstractString) = Node(COMMENT, nothing, nothing, String(value))

"""
    cdata(value::AbstractString)

Create an `XML.Node` with `nodetype=CDATA` and the provided `value`.
"""
cdata(value::AbstractString) = Node(CDATA, nothing, nothing, String(value))

"""
    text(value::AbstractString)

Create an `XML.Node` with `nodetype=TEXT` and the provided `value`.
"""
text(value::AbstractString) = Node(TEXT, nothing, nothing, String(value))

"""
    element(tag children::Vector{Node}; attributes...)
    element(tag, children::Node...; attributes...)
    element(tag, children::Vector{Node}, attributes::Dict{String,String})

Create an `XML.Node` with `nodetype=ELEMENT` and the provided `tag`, `children`, and `attributes`.
"""
element(tag, children...; kw...) = Node(ELEMENT, string(tag), attrs(kw), nothing, map(Node, collect(children)))
element(tag, children::Vector{Node}; kw...) = element(tag, children...; kw...)
element(tag, children::Vector{Node}, attrs::Dict{String,String}) = Node(ELEMENT, tag, attrs, nothing, children)
end  # module NodeConstructors







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
    if o.nodetype === TEXT
        printstyled(io, ' ', repr(value(o)))
    elseif o.nodetype === ELEMENT
        printstyled(io, " <", tag(o), color=:light_cyan)
        _print_attrs(io, o)
        printstyled(io, '>', color=:light_cyan)
        _print_n_children(io, o)
    elseif o.nodetype === DTD
        printstyled(io, " <!DOCTYPE "; color=:light_cyan)
        printstyled(io, value(o), color=:light_black)
        printstyled(io, '>', color=:light_cyan)
    elseif o.nodetype === DECLARATION
        printstyled(io, " <?xml", color=:light_cyan)
        _print_attrs(io, o)
        printstyled(io, "?>", color=:light_cyan)
    elseif o.nodetype === PROCESSING_INSTRUCTION
        printstyled(io, " <?", tag(o), color=:light_cyan)
        _print_attrs(io, o)
        printstyled(io, "?>", color=:light_cyan)
    elseif o.nodetype === COMMENT
        printstyled(io, " <!--", color=:light_cyan)
        printstyled(io, value(o), color=:light_black)
        printstyled(io, "-->", color=:light_cyan)
    elseif o.nodetype === CDATA
        printstyled(io, " <![CDATA[", color=:light_cyan)
        printstyled(io, value(o), color=:light_black)
        printstyled(io, "]]>", color=:light_cyan)
    elseif o.nodetype === DOCUMENT
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
    if nodetype === TEXT
        print(io, escape(value))
    elseif nodetype === ELEMENT
        print(io, '<', tag)
        _print_attrs(io, x)
        print(io, isempty(children) ? '/' : "", '>')
        if !isempty(children)
            if length(children) == 1 && XML.nodetype(only(children)) === TEXT
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
    elseif nodetype === DECLARATION
        print(io, "<?xml")
        _print_attrs(io, x)
        print(io, "?>")
    elseif nodetype === PROCESSING_INSTRUCTION
        print(io, "<?", tag)
        _print_attrs(io, x)
        print(io, "?>")
    elseif nodetype === COMMENT
        print(io, "<!--", value, "-->")
    elseif nodetype === CDATA
        print(io, "<![CDATA[", value, "]]>")
    elseif nodetype === DOCUMENT
        foreach(children) do child
            write(io, child; indent)
            println(io)
        end
    else
        error("Unreachable case reached during XML.write")
    end
end

end
