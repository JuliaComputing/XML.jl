module XML

using StyledStrings

export
    read_xml, write_xml,
    Text, Comment, CData

#-----------------------------------------------------------------------------# escape/unescape
const escape_chars = ('&' => "&amp;", '<' => "&lt;", '>' => "&gt;", "'" => "&apos;", '"' => "&quot;")
unescape(x::AbstractString) = replace(x, reverse.(escape_chars)...)
escape(x::AbstractString) = replace(x, escape_chars...)

#-----------------------------------------------------------------------------# utils
function roundtrip(x)
    io = IOBuffer()
    write_xml(io, x)
    seekstart(io)
    return x == read_xml(io, typeof(x))
end

function peek_str(io::IO, n::Integer)
    pos = position(io)
    out = String(read(io, n))
    seek(io, pos)
    return out
end

#-----------------------------------------------------------------------------# Attributes
struct Attributes <: AbstractDict{Symbol, String}
    keys::Vector{Symbol}
    values::Vector{String}
end
function Attributes(pairs::Pair...)
    keys = [Symbol(x) for x in first.(pairs)]
    values = [string(x) for x in last.(pairs)]
    Attributes(keys, values)
end
Attributes(; kw...) = Attributes(collect(kw)...)

Base.keys(o::Attributes) = getfield(o, :keys)
Base.values(o::Attributes) = getfield(o, :values)
Base.length(o::Attributes) = length(keys(o))
Base.iterate(o::Attributes, i=1) = i > length(o) ? nothing : (keys(o)[i] => values(o)[i], i + 1)

function Base.getindex(o::Attributes, k::Symbol)
    i = findfirst(==(k), keys(o))
    isnothing(i) ? throw(KeyError(k)) : values(o)[i]
end
Base.getindex(o::Attributes, x::AbstractString) = o[Symbol(x)]
Base.getindex(o::Attributes, i::Integer) = keys(o)[i] => values(o)[i]
function Base.setindex!(o::Attributes, v, k::Symbol)
    i = findfirst(==(k), keys(o))
    if isnothing(i)
        push!(keys(o), k)
        push!(values(o), string(v))
    else
        values(o)[i] = string(v)
    end
    return v
end

Base.propertynames(o::Attributes) = keys(o)
Base.getproperty(o::Attributes, k::Symbol) = getindex(o, k)
Base.setproperty!(o::Attributes, k::Symbol, v) = setindex!(o, v, k)

#-----------------------------------------------------------------------------# Types
# Document, DTD, Declaration, ProcessingInstruction, CData, Element

abstract type XMLNode end

write_xml(x) = sprint(write_xml, x)

read_xml(str::AbstractString, ::Type{T}) where {T <: XMLNode} = read_xml(IOBuffer(str), T)

is_next(s::AbstractString, ::Type{T}) where {T <: XMLNode} = is_next(IOBuffer(s), T)

function Base.show(io::IO, o::T) where {T <: XMLNode}
    str = sprint(write_xml, o)
    # TODO: more compact representation
    print(io, T.name.name, ": ", styled"{bright_black:$str}")
end

#-----------------------------------------------------------------------------# Text
struct Text{T <: AbstractString} <: XMLNode
    value::T
end
write_xml(io::IO, o::Text) = print(io, o.value)
read_xml(io::IO, o::Type{T}) where {T <: Text} = Text(readuntil(io, '<'))
is_next(io::IO, o::Type{T}) where {T <: Text} = peek(io, Char) != '<'

#-----------------------------------------------------------------------------# Comment
struct Comment{T <: AbstractString} <: XMLNode
    value::T
end
write_xml(io::IO, o::Comment) = print(io, "<!--", o.value, "-->")
function read_xml(io::IO, ::Type{T}) where {T <: Comment}
    readuntil(io, "<!--", keep=true)
    s = readuntil(io, "-->")
    read(io, 3)
    Comment(s)
end
is_next(io::IO, ::Type{T}) where {T <: Comment} = peek_str(io, 4) == "<!--"

#-----------------------------------------------------------------------------# CData
struct CData{T <: AbstractString} <: XMLNode
    value::T
end
write_xml(io::IO, o::CData) = print(io, "<![CDATA[", o.value, "]]>")
function read_xml(io::IO, ::Type{T}) where {T <: CData}
    readuntil(io, "<![CDATA[", keep=true)
    s = readuntil(io, "]]>")
    read(io, 3)
    CData(s)
end
is_next(io::IO, ::Type{T}) where {T <: CData} = peek_str(io, 9) == "<![CDATA["

# struct ProcessingInstruction{T <: AbstractString} <: XMLNode
#     target::T
#     data::T
# end
# xml(io::IO, o::ProcessingInstruction) = print(io, "<?", o.target, " ", o.data, "?>")

# struct Declaration{T <: AbstractString} <: XMLNode
#     version::T
#     encoding::T
#     standalone::Bool
# end
# xml(io::IO, o::Declaration) = print(io, "<?xml version=\"", o.version, "\" encoding=\"", o.encoding, "\" standalone=\"", o.standalone ? "yes" : "no", "\"?>")

# struct Element{T} <: XMLNode
#     name::Symbol
#     attributes::Attributes
#     children::Vector{Union{Element{T}, Text{T}, CData{T}, Comment{T}}}
# end


# struct DTD{T} <: XMLNode
#     value::T
# end

# struct Document{T} <: XMLNode
#     prolog::Vector{Union{ProcessingInstruction{T}, DTD{T},  Declaration{T}, Comment{T}}}
#     root::Element{T}
# end

# #-----------------------------------------------------------------------------# printing
# xml(x) = sprint(xml, x)

# function xml(io::IO, x)
#     print_open_tag_begin(io, x)
#     print_attributes(io, x)
#     print_open_tag_end(io, x)
#     print_children(io, x)
#     print_close_tag(io, x)
# end

# print_open_tag_begin(io::IO, x) = nothing
# print_attributes(io::IO, x) = nothing
# print_open_tag_end(io::IO, x) = nothing
# print_children(io::IO, x) = nothing
# print_close_tag(io::IO, x) = nothing


# #-----------------------------------------------------------------------------# NodeType
# """
#     NodeType:
#     - Document                  # prolog & root Element
#     - DTD                       # <!DOCTYPE ...>
#     - Declaration               # <?xml attributes... ?>
#     - ProcessingInstruction     # <?NAME attributes... ?>
#     - Comment                   # <!-- ... -->
#     - CData                     # <![CData[...]]>
#     - Element                   # <NAME attributes... > children... </NAME>
#     - Text                      # text

# NodeTypes can be used to construct XML.Nodes:

#     Document(children...)
#     DTD(value)
#     Declaration(; attributes)
#     ProcessingInstruction(tag, attributes)
#     Comment(text)
#     CData(text)
#     Element(tag, children...; attributes)
#     Text(text)
# """
# @enum(NodeType, CData, Comment, Declaration, Document, DTD, Element, ProcessingInstruction, Text)


# #-----------------------------------------------------------------------------# includes
# include("raw.jl")
# include("dtd.jl")

# abstract type AbstractXMLNode end

#-----------------------------------------------------------------------------# LazyNode
# """
#     LazyNode(file::AbstractString)
#     LazyNode(data::XML.Raw)

# A Lazy representation of an XML node.
# """
# mutable struct LazyNode <: AbstractXMLNode
#     raw::Raw
#     tag::Union{Nothing, String}
#     attributes::Union{Nothing, OrderedDict{String, String}}
#     value::Union{Nothing, String}
# end
# LazyNode(raw::Raw) = LazyNode(raw, nothing, nothing, nothing)

# function Base.getproperty(o::LazyNode, x::Symbol)
#     x === :raw && return getfield(o, :raw)
#     x === :nodetype && return nodetype(o.raw)
#     x === :tag && return isnothing(getfield(o, x)) ? setfield!(o, x, tag(o.raw)) : getfield(o, x)
#     x === :attributes && return isnothing(getfield(o, x)) ? setfield!(o, x, attributes(o.raw)) : getfield(o, x)
#     x === :value && return isnothing(getfield(o, x)) ? setfield!(o, x, value(o.raw)) : getfield(o, x)
#     x === :depth && return depth(o.raw)
#     x === :children && return LazyNode.(children(o.raw))
#     error("type LazyNode has no field $(x)")
# end
# Base.propertynames(o::LazyNode) = (:raw, :nodetype, :tag, :attributes, :value, :depth, :children)

# Base.show(io::IO, o::LazyNode) = _show_node(io, o)

# Base.read(io::IO, ::Type{LazyNode}) = LazyNode(read(io, Raw))
# Base.read(filename::AbstractString, ::Type{LazyNode}) = LazyNode(read(filename, Raw))
# Base.parse(x::AbstractString, ::Type{LazyNode}) = LazyNode(parse(x, Raw))

# children(o::LazyNode) = LazyNode.(children(o.raw))
# parent(o::LazyNode) = LazyNode(parent(o.raw))
# depth(o::LazyNode) = depth(o.raw)

# Base.IteratorSize(::Type{LazyNode}) = Base.SizeUnknown()
# Base.eltype(::Type{LazyNode}) = LazyNode

# function Base.iterate(o::LazyNode, state=o)
#     n = next(state)
#     return isnothing(n) ? nothing : (n, n)
# end

# function next(o::LazyNode)
#     n = next(o.raw)
#     isnothing(n) && return nothing
#     n.type === RawElementClose ? next(LazyNode(n)) : LazyNode(n)
# end
# function prev(o::LazyNode)
#     n = prev(o.raw)
#     isnothing(n) && return nothing
#     n.type === RawElementClose ? prev(LazyNode(n)) : LazyNode(n)
# end

# #-----------------------------------------------------------------------------# Node
# """
#     Node(nodetype, tag, attributes, value, children)
#     Node(node::Node; kw...)  # copy node with keyword overrides
#     Node(node::LazyNode)  # un-lazy the LazyNode

# A representation of an XML DOM node.  For simpler construction, use `(::NodeType)(args...)`
# """
# struct Node <: AbstractXMLNode
#     nodetype::NodeType
#     tag::Union{Nothing, String}
#     attributes::Union{Nothing, OrderedDict{String, String}}
#     value::Union{Nothing, String}
#     children::Union{Nothing, Vector{Node}}

#     function Node(nodetype::NodeType, tag=nothing, attributes=nothing, value=nothing, children=nothing)
#         new(nodetype,
#             isnothing(tag) ? nothing : string(tag),
#             isnothing(attributes) ? nothing : OrderedDict(string(k) => string(v) for (k, v) in pairs(attributes)),
#             isnothing(value) ? nothing : string(value),
#             isnothing(children) ? nothing :
#                 children isa Node ? [children] :
#                 children isa Vector{Node} ? children :
#                 children isa Vector ? map(Node, children) :
#                 children isa Tuple ? map(Node, collect(children)) :
#                 [Node(children)]
#         )
#     end
# end

# function Node(o::Node, x...; kw...)
#     attrs = !isnothing(kw) ?
#         merge(
#             OrderedDict(string(k) => string(v) for (k,v) in pairs(kw)),
#             isnothing(o.attributes) ? OrderedDict{String, String}() : o.attributes
#         ) :
#         o.attributes
#     children = isempty(x) ? o.children : vcat(isnothing(o.children) ? [] : o.children, collect(x))
#     Node(o.nodetype, o.tag, attrs, o.value, children)
# end

# function Node(node::LazyNode)
#     nodetype = node.nodetype
#     tag = node.tag
#     attributes = node.attributes
#     value = node.value
#     c = XML.children(node)
#     Node(nodetype, tag, attributes, value, isempty(c) ? nothing : map(Node, c))
# end

# Node(data::Raw) = Node(LazyNode(data))

# # Anything that's not Vector{UInt8} or a (Lazy)Node is converted to a Text Node
# Node(x) = Node(Text, nothing, nothing, string(x), nothing)

# h(tag::Union{Symbol, String}, children...; kw...) = Node(Element, tag, kw, nothing, children)
# Base.getproperty(::typeof(h), tag::Symbol) = h(tag)
# (o::Node)(children...; kw...) = Node(o, Node.(children)...; kw...)

# # NOT in-place for Text Nodes
# function escape!(o::Node, warn::Bool=true)
#     if o.nodetype == Text
#         warn && @warn "escape!() called on a Text Node creates a new node."
#         return Text(escape(o.value))
#     end
#     isnothing(o.children) && return o
#     map!(x -> escape!(x, false), o.children, o.children)
#     o
# end
# function unescape!(o::Node, warn::Bool=true)
#     if o.nodetype == Text
#         warn && @warn "unescape!() called on a Text Node creates a new node."
#         return Text(unescape(o.value))
#     end
#     isnothing(o.children) && return o
#     map!(x -> unescape!(x, false), o.children, o.children)
#     o
# end


# Base.read(filename::AbstractString, ::Type{Node}) = Node(read(filename, Raw))
# Base.read(io::IO, ::Type{Node}) = Node(read(io, Raw))
# Base.parse(x::AbstractString, ::Type{Node}) = Node(parse(x, Raw))

# Base.setindex!(o::Node, val, i::Integer) = o.children[i] = Node(val)
# Base.push!(a::Node, b::Node) = push!(a.children, b)
# Base.pushfirst!(a::Node, b::Node) = pushfirst!(a.children, b)

# Base.setindex!(o::Node, val, key::AbstractString) = (o.attributes[key] = string(val))
# Base.getindex(o::Node, val::AbstractString) = o.attributes[val]
# Base.haskey(o::Node, key::AbstractString) = isnothing(o.attributes) ? false : haskey(o.attributes, key)
# Base.keys(o::Node) = isnothing(o.attributes) ? () : keys(o.attributes)

# Base.show(io::IO, o::Node) = _show_node(io, o)

# #-----------------------------------------------------------------------------# Node Constructors
# function (T::NodeType)(args...; attr...)
#     if T === Document
#         !isempty(attr) && error("Document nodes do not have attributes.")
#         Node(T, nothing, nothing, nothing, args)
#     elseif T === DTD
#         !isempty(attr) && error("DTD nodes only accept a value.")
#         length(args) > 1 && error("DTD nodes only accept a value.")
#         Node(T, nothing, nothing, only(args))
#     elseif T === Declaration
#         !isempty(args) && error("Declaration nodes only accept attributes")
#         Node(T, nothing, attr)
#     elseif T === ProcessingInstruction
#         length(args) == 1 || error("ProcessingInstruction nodes require a tag and attributes.")
#         Node(T, only(args), attr)
#     elseif T === Comment
#         !isempty(attr) && error("Comment nodes do not have attributes.")
#         length(args) > 1 && error("Comment nodes only accept a single input.")
#         Node(T, nothing, nothing, only(args))
#     elseif T === CData
#         !isempty(attr) && error("CData nodes do not have attributes.")
#         length(args) > 1 && error("CData nodes only accept a single input.")
#         Node(T, nothing, nothing, only(args))
#     elseif T === Text
#         !isempty(attr) && error("Text nodes do not have attributes.")
#         length(args) > 1 && error("Text nodes only accept a single input.")
#         Node(T, nothing, nothing, only(args))
#     elseif T === Element
#         tag = first(args)
#         Node(T, tag, attr, nothing, args[2:end])
#     else
#         error("Unreachable reached while trying to create a Node via (::NodeType)(args...; kw...).")
#     end
# end

# #-----------------------------------------------------------------------------# !!! common !!!
# # Everything below here is common to all data structures


# #-----------------------------------------------------------------------------# interface fallbacks
# nodetype(o) = o.nodetype
# tag(o) = o.tag
# attributes(o) = o.attributes
# value(o) = o.value
# children(o::T) where {T} = isnothing(o.children) ? () : o.children

# depth(o) = missing
# parent(o) = missing
# next(o) = missing
# prev(o) = missing

# is_simple(o) = nodetype(o) == Element && (isnothing(attributes(o)) || isempty(attributes(o))) &&
#     length(children(o)) == 1 && nodetype(only(o)) in (Text, CData)

# simple_value(o) = is_simple(o) ? value(only(o)) : error("`XML.simple_value` is only defined for simple nodes.")

# Base.@deprecate_binding simplevalue simple_value

# #-----------------------------------------------------------------------------# nodes_equal
# function nodes_equal(a, b)
#     out = XML.tag(a) == XML.tag(b)
#     out &= XML.nodetype(a) == XML.nodetype(b)
#     out &= XML.attributes(a) == XML.attributes(b)
#     out &= XML.value(a) == XML.value(b)
#     out &= length(XML.children(a)) == length(XML.children(b))
#     out &= all(nodes_equal(ai, bi) for (ai,bi) in zip(XML.children(a), XML.children(b)))
#     return out
# end

# Base.:(==)(a::AbstractXMLNode, b::AbstractXMLNode) = nodes_equal(a, b)

# #-----------------------------------------------------------------------------# parse
# Base.parse(::Type{T}, str::AbstractString) where {T <: AbstractXMLNode} = parse(str, T)

# #-----------------------------------------------------------------------------# indexing
# Base.getindex(o::Union{Raw, AbstractXMLNode}) = o
# Base.getindex(o::Union{Raw, AbstractXMLNode}, i::Integer) = children(o)[i]
# Base.getindex(o::Union{Raw, AbstractXMLNode}, ::Colon) = children(o)
# Base.lastindex(o::Union{Raw, AbstractXMLNode}) = lastindex(children(o))

# Base.only(o::Union{Raw, AbstractXMLNode}) = only(children(o))

# Base.length(o::AbstractXMLNode) = length(children(o))

# #-----------------------------------------------------------------------------# printing
# function _show_node(io::IO, o)
#     printstyled(io, typeof(o), ' '; color=:light_black)
#     !ismissing(depth(o)) && printstyled(io, "(depth=", depth(o), ") ", color=:light_black)
#     printstyled(io, nodetype(o), ; color=:light_green)
#     if o.nodetype === Text
#         printstyled(io, ' ', repr(value(o)))
#     elseif o.nodetype === Element
#         printstyled(io, " <", tag(o), color=:light_cyan)
#         _print_attrs(io, o; color=:light_yellow)
#         printstyled(io, '>', color=:light_cyan)
#         _print_n_children(io, o)
#     elseif o.nodetype === DTD
#         printstyled(io, " <!DOCTYPE "; color=:light_cyan)
#         printstyled(io, value(o), color=:light_black)
#         printstyled(io, '>', color=:light_cyan)
#     elseif o.nodetype === Declaration
#         printstyled(io, " <?xml", color=:light_cyan)
#         _print_attrs(io, o; color=:light_yellow)
#         printstyled(io, "?>", color=:light_cyan)
#     elseif o.nodetype === ProcessingInstruction
#         printstyled(io, " <?", tag(o), color=:light_cyan)
#         _print_attrs(io, o; color=:light_yellow)
#         printstyled(io, "?>", color=:light_cyan)
#     elseif o.nodetype === Comment
#         printstyled(io, " <!--", color=:light_cyan)
#         printstyled(io, value(o), color=:light_black)
#         printstyled(io, "-->", color=:light_cyan)
#     elseif o.nodetype === CData
#         printstyled(io, " <![CData[", color=:light_cyan)
#         printstyled(io, value(o), color=:light_black)
#         printstyled(io, "]]>", color=:light_cyan)
#     elseif o.nodetype === Document
#         _print_n_children(io, o)
#     elseif o.nodetype === UNKNOWN
#         printstyled(io, "Unknown", color=:light_cyan)
#         _print_n_children(io, o)
#     else
#         error("Unreachable reached")
#     end
# end

# function _print_attrs(io::IO, o; color=:normal)
#     attr = attributes(o)
#     isnothing(attr) && return nothing
#     for (k,v) in attr
#         # printstyled(io, ' ', k, '=', '"', v, '"'; color)
#         print(io, ' ', k, '=', '"', v, '"')
#     end
# end
# function _print_n_children(io::IO, o::Node)
#     n = length(children(o))
#     text = n == 0 ? "" : n == 1 ? " (1 child)" : " ($n children)"
#     printstyled(io, text, color=:light_black)
# end
# _print_n_children(io::IO, o) = nothing

# #-----------------------------------------------------------------------------# write_xml
# write(x; kw...) = (io = IOBuffer(); write(io, x; kw...); String(take!(io)))

# write(filename::AbstractString, x; kw...) = open(io -> write(io, x; kw...), filename, "w")

# function write(io::IO, x; indentsize::Int=2, depth::Int=1)
#     indent = ' ' ^ indentsize
#     nodetype = XML.nodetype(x)
#     tag = XML.tag(x)
#     value = XML.value(x)
#     children = XML.children(x)

#     padding = indent ^ max(0, depth - 1)
#     print(io, padding)
#     if nodetype === Text
#         print(io, value)
#     elseif nodetype === Element
#         print(io, '<', tag)
#         _print_attrs(io, x)
#         print(io, isempty(children) ? '/' : "", '>')
#         if !isempty(children)
#             if length(children) == 1 && XML.nodetype(only(children)) === Text
#                 write(io, only(children); indentsize=0)
#                 print(io, "</", tag, '>')
#             else
#                 println(io)
#                 foreach(children) do child
#                     write(io, child; indentsize, depth = depth + 1)
#                     println(io)
#                 end
#                 print(io, padding, "</", tag, '>')
#             end
#         end
#     elseif nodetype === DTD
#         print(io, "<!DOCTYPE ", value, '>')
#     elseif nodetype === Declaration
#         print(io, "<?xml")
#         _print_attrs(io, x)
#         print(io, "?>")
#     elseif nodetype === ProcessingInstruction
#         print(io, "<?", tag)
#         _print_attrs(io, x)
#         print(io, "?>")
#     elseif nodetype === Comment
#         print(io, "<!--", value, "-->")
#     elseif nodetype === CData
#         print(io, "<![CData[", value, "]]>")
#     elseif nodetype === Document
#         foreach(children) do child
#             write(io, child; indentsize)
#             println(io)
#         end
#     else
#         error("Unreachable case reached during XML.write")
#     end
# end

end
