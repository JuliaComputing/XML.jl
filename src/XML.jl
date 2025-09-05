module XML

using StyledStrings, StringViews

export tokens, escape, unescape

#-----------------------------------------------------------------------------# escape/unescape
const escape_chars = ('&' => "&amp;", '<' => "&lt;", '>' => "&gt;", "'" => "&apos;", '"' => "&quot;")
unescape(x::AbstractString) = replace(x, reverse.(escape_chars)...)
escape(x::AbstractString) = replace(x, escape_chars...)


#-----------------------------------------------------------------------------# Token
@enum TokenType begin
    UNKNOWN_TOKEN       # ?
    TAGSTART_TOKEN      # <tag
    TAGEND_TOKEN        # >
    TAGCLOSE_TOKEN      # </tag>
    TAGSELFCLOSE_TOKEN  # />
    EQUALS_TOKEN        # =
    ATTRKEY_TOKEN       # attr
    ATTRVAL_TOKEN       # "value"
    TEXT_TOKEN          # between > and <
    PI_TOKEN            # <? ... ?>
    DECL_TOKEN          # <?xml ... ?>
    COMMENT_TOKEN       # <!-- ... -->
    CDATA_TOKEN         # <![CDATA[ ... ]]>
    DTD_TOKEN           # <!DOCTYPE ... >
    WS_TOKEN            # " \t\n\r"
end

struct Token{T <: AbstractVector{UInt8}}
    data::T
    type::TokenType
    in_tag::Bool
    i::Int
    j::Int
end
Token(data) = Token(data, UNKNOWN_TOKEN, false, 1, 0)
(t::Token)(type, in_tag, j) = Token(t.data, type, in_tag, t.i, j)

# Add _ separator for large Ints
format(x::Int) = replace(string(x), r"(\d)(?=(\d{3})+(?!\d))" => s"\1_")

function Base.show(io::IO, t::Token)
    print(io, styled"{bright_yellow:$(rpad(t.type, 19))}", " ", format(t.i), " → ", format(t.j))
    print(io, styled" {bright_black:($(Base.format_bytes(ncodeunits(StringView(t)))))}")
    s = repr(StringView(t))[2:end-1]
    t.in_tag ?
        print(io, styled": {inverse:{bright_cyan:$s}}") :
        print(io, styled": {inverse:{bright_green:$s}}")
end

Base.view(t::Token) = view(t.data, t.i:t.j)
StringViews.StringView(t::Token) = StringView(view(t))

function next(t::Token)
    t.j == length(t.data) && return nothing
    t = Token(t.data, t.type, t.in_tag, t.j + 1, length(t.data))
    sv = StringView(t::Token)
    c = sv[1]

    if t.in_tag
        startswith(sv, '>') && return t(TAGEND_TOKEN, false, t.i)
        startswith(sv, "/>") && return t(TAGSELFCLOSE_TOKEN, false, t.i + 1)
        c == '"' && return t(ATTRVAL_TOKEN, true, t.i + findnext('"', sv, 2) - 1)
        c == ''' && return t(ATTRVAL_TOKEN, true, t.i + findnext(''', sv, 2) - 1)
        is_name_start_char(c) && return t(ATTRKEY_TOKEN, true, t.i + findnext(!is_name_char, sv, 2) - 2)
        c == '=' && return t(EQUALS_TOKEN, true, t.i)
    elseif c == '<'
        c2 = sv[2]
        is_name_start_char(c2) && return t(TAGSTART_TOKEN, true, t.i + findnext(!is_name_char, sv, 2) - 2)
        startswith(sv, "</") && return t(TAGCLOSE_TOKEN, false, t.i + findnext('>', sv, 3) - 1)
        startswith(sv, "<!--") && return t(COMMENT_TOKEN, false, t.i + findnext("-->", sv, 5)[end] - 1)
        startswith(sv, "<![CDATA[") && return t(CDATA_TOKEN, false, t.i + findnext("]]>", sv, 10)[end] - 1)
        startswith(sv, "<?xml ") && return t(DECL_TOKEN, false, t.i + findnext("?>", sv, 7)[end] - 1)
        startswith(sv, "<?") && return t(PI_TOKEN, false, t.i + findnext("?>", sv, 4)[end] - 1)
        startswith(sv, "<!DOCTYPE") && return t(DTD_TOKEN, false, t.i + findnext('>', sv, 10) - 1)
    end
    if is_ws(c)
        j = findnext(!is_ws, sv, 2)
        j = isnothing(j) ? length(t.data) : t.i + j - 2
        return t(WS_TOKEN, t.in_tag, j)
    end
    return t(TEXT_TOKEN, false, t.i + findnext('<', sv, 2) - 2)
end

is_ws(x::Char) = x == ' ' || x == '\t' || x == '\n' || x == '\r'

function is_name_start_char(c::Char)
    c == ':' || c == '_' ||
    ('A' ≤ c ≤ 'Z') || ('a' ≤ c ≤ 'z') ||
    ('\u00C0' ≤ c ≤ '\u00D6') ||
    ('\u00D8' ≤ c ≤ '\u00F6') ||
    ('\u00F8' ≤ c ≤ '\u02FF') ||
    ('\u0370' ≤ c ≤ '\u037D') ||
    ('\u037F' ≤ c ≤ '\u1FFF') ||
    ('\u200C' ≤ c ≤ '\u200D') ||
    ('\u2070' ≤ c ≤ '\u218F') ||
    ('\u2C00' ≤ c ≤ '\u2FEF') ||
    ('\u3001' ≤ c ≤ '\uD7FF') ||
    ('\uF900' ≤ c ≤ '\uFDCF') ||
    ('\uFDF0' ≤ c ≤ '\uFFFD') ||
    ('\U00010000' ≤ c ≤ '\U000EFFFF')
end
function is_name_char(c::Char)
    is_name_start_char(c) ||
    c == '-' || c == '.' ||
    ('0' ≤ c ≤ '9') ||
    c == '\u00B7' ||
    ('\u0300' ≤ c ≤ '\u036F') ||
    ('\u203F' ≤ c ≤ '\u2040')
end


Base.IteratorSize(::Type{T}) where {T <: Token} = Base.SizeUnknown()
Base.eltype(::Type{T}) where {S, T <: Token{S}} = T
Base.isdone(o::Token{T}, t::Token{T}) where {T} = t.j == length(t.data)
function Base.iterate(t::Token, state=t)
    n = next(state)
    isnothing(n) && return nothing
    return (n, n)
end

tokens(file::AbstractString) = collect(Token(read(file)))
tokens(io::IO) = collect(Token(read(io)))

#-----------------------------------------------------------------------------# Node
@enum Kind UNKNOWN CDATA COMMENT DECLARATION DOCUMENT FRAGMENT DTD ELEMENT PI TEXT

struct Node{T <: AbstractString}
    kind::Kind
    preserve_space_stack::Vector{Bool}
    name::Union{T, Nothing}
    attributes::Union{Vector{Pair{T, T}}, Nothing}
    value::Union{T, Nothing}
    children::Union{Vector{Node{T}}, Nothing}
end


# #-----------------------------------------------------------------------------# Lexer
# # Iterates same tokens as Token...minus insignificant WS_TOKENs
# struct Lexer{T <: AbstractVector{UInt8}}
#     data::T
# end

# Base.IteratorSize(::Type{Lexer{T}}) where {T} = Base.SizeUnknown()
# Base.eltype(::Type{Lexer{T}}) where {T} = Token{T}
# Base.isdone(o::Lexer{T}, t::Token{T}) where {T} = t.j == length(t.data)
# function Base.iterate(o::Lexer, (; token=Token(o.data), check_val=false, preserve_stack=[false]))
#     n = next(token)
#     isnothing(n) && return nothing
#     if n.type == ATTRKEY_TOKEN && StringView(n) == "xml:space"
#         state = (; token=n, check_val=true, preserve)
#         return (n, state)
#     elseif n.type == ATTRVAL_TOKEN && check_val
#         s = @view StringView(n)[2:end-1]
#         preserve = s == "preserve"
#         state = (; token=n, check_val=false, preserve)
#         return (n, state)
# end


# #-----------------------------------------------------------------------------# FileNode
# @enum Kind UNKNOWN CDATA COMMENT DECLARATION DOCUMENT FRAGMENT DTD ELEMENT PI TEXT

# struct TokenNode{T}
#     tokens::Token{T}
#     preserve::Vector{Bool}
#     kind::Kind
#     cursor::Int
# end

# function TokenNode(toks::Vector{Token{T}}) where {T}
#     preserve = falses(length(toks))
#     check_val = false
#     for (i, t) in enumerate(toks)
#         if t.type == ATTRKEY_TOKEN && StringView(t) == "xml:space"
#             check_val = true
#         elseif t.type == ATTRVAL_TOKEN && check_val
#             s = @view StringView(t)[2:end-1]

#         end

#     end
# end


# """
#     File(s::AbstractString)

# Wrapper around `Vector{Token{T}}` with insignificant whitespace removed.
# """
# struct File{T}
#     tokens::Token{T}
# end

# # Sequence we need to look out for:
# #   - `ATTRKEY (xml:space) → WS? → EQUALS → WS? → ATTRVAL ("preserve | default")`
# function File(s::AbstractString)
#     toks = tokens(s)
#     out = eltype(toks)[]
#     preserve_space_stack = Bool[]
#     for t in toks
#         if isempty(preserve_space_stack)
#             t.type != WS_TOKEN && push!(out, t)
#         else

#         end
#     end
#     return out
# end


#-----------------------------------------------------------------------------# Node
# @enum Kind UNKNOWN CDATA COMMENT DECLARATION DOCUMENT FRAGMENT DTD ELEMENT PI TEXT

# struct Node{T <: AbstractString}
#     kind::Kind
#     preserve_space_stack::Vector{Bool}
#     name::Union{T, Nothing}
#     attributes::Union{Vector{Pair{T, T}}, Nothing}
#     value::Union{T, Nothing}
#     children::Union{Vector{Node{T}}, Nothing}
# end

# function document(s::T) where {T <: AbstractString}
#     out = Node{T}(DOCUMENT, Bool[], nothing, nothing, nothing, Node{T}[])
# end


# #-----------------------------------------------------------------------------# utils
# function roundtrip(x)
#     io = IOBuffer()
#     write_xml(io, x)
#     seekstart(io)
#     return x == read_xml(io, typeof(x))
# end

# function peek_str(io::IO, n::Integer)
#     pos = position(io)
#     out = String(read(io, n))
#     seek(io, pos)
#     return out
# end

# is_name_start_char(x::Char) = isletter(x) || x == ':' || x == '_'

# #-----------------------------------------------------------------------------# XMLNode
# abstract type XMLNode end

# write_xml(x) = sprint(write_xml, x)

# read_xml(str::AbstractString, ::Type{T}) where {T <: XMLNode} = read_xml(IOBuffer(str), T)

# is_next(s::AbstractString, ::Type{T}) where {T <: XMLNode} = is_next(IOBuffer(s), T)

# function Base.show(io::IO, o::T) where {T <: XMLNode}
#     str = sprint(write_xml, o)
#     # TODO: more compact representation
#     print(io, T.name.name, ": ", styled"{bright_black:$str}")
# end

# #-----------------------------------------------------------------------------# Text
# """
#     Text(value::AbstractString)
#     # value
# """
# struct Text{T <: AbstractString} <: XMLNode
#     value::T
# end
# write_xml(io::IO, o::Text) = print(io, o.value)
# read_xml(io::IO, o::Type{T}) where {T <: Text} = Text(readuntil(io, '<'))
# is_next(io::IO, o::Type{T}) where {T <: Text} = peek(io, Char) != '<'

# #-----------------------------------------------------------------------------# Comment
# """
#     Comment(value::AbstractString)
#     # <!-- value -->
# """
# struct Comment{T <: AbstractString} <: XMLNode
#     value::T
# end
# write_xml(io::IO, o::Comment) = print(io, "<!--", o.value, "-->")
# function read_xml(io::IO, ::Type{T}) where {T <: Comment}
#     read(io, 4) # <!--
#     return Comment(readuntil(io, "-->"))
# end
# is_next(io::IO, ::Type{T}) where {T <: Comment} = peek_str(io, 4) == "<!--"


# #-----------------------------------------------------------------------------# CData
# """
#     CData(value::AbstractString)
#     # <![CDATA[ value ]]>
# """
# struct CData{T <: AbstractString} <: XMLNode
#     value::T
# end
# write_xml(io::IO, o::CData) = print(io, "<![CDATA[", o.value, "]]>")
# function read_xml(io::IO, ::Type{T}) where {T <: CData}
#     read(io, 9)  # <![CDATA[
#     CData(readuntil(io, "]]>"))
# end
# is_next(io::IO, ::Type{T}) where {T <: CData} = peek_str(io, 9) == "<![CDATA["


# #-----------------------------------------------------------------------------# ProcessingInstruction
# """
#     ProcessingInstruction(target::AbstractString, data::AbstractString)
#     # <?target data?>
# """
# struct ProcessingInstruction{T <: AbstractString} <: XMLNode
#     target::T
#     data::T
# end
# ProcessingInstruction(target::T; kw...) where {T} = ProcessingInstruction(target, join([T("$k=\"$v\"") for (k, v) in kw]))
# write_xml(io::IO, o::ProcessingInstruction) = print(io, "<?", o.target, " ", o.data, "?>")
# function read_xml(io::IO, ::Type{T}) where {T <: ProcessingInstruction}
#     read(io, 2)  # <?
#     target = readuntil(io, ' ')
#     data = readuntil(io, "?>")
#     return ProcessingInstruction(target, data)
# end
# is_next(io::IO, ::Type{T}) where {T <: ProcessingInstruction} = peek_str(io, 2) == "<?" && peek_str(io, 5) != "<?xml"


# #-----------------------------------------------------------------------------# Declaration
# """
#     Declaration(version = "1.0", encoding="UTF-8", standalone="no")
#     # <?xml version="1.0" encoding="UTF-8" standalone="no"?>
# """
# struct Declaration{T <: AbstractString} <: XMLNode
#     version::T
#     encoding::Union{Nothing, T}
#     standalone::Union{Nothing, Bool}
# end
# function write_xml(io::IO, o::Declaration)
#     print(io, "<?xml version=", repr(o.version))
#     !isnothing(o.encoding) && print(" encoding=", repr(o.encoding))
#     !isnothing(o.standalone) && print(" standalone=", repr(o.standalone ? "yes" : "no"))
#     print(io, "?>")
# end
# function read_xml(io::IO, ::Type{T}) where {T <: Declaration}
#     read(io, 5)  # <?xml
#     readuntil(io, "version")
#     readuntil(io, "=")
#     readuntil(io, '"')
#     version = readuntil(io, '"')
# end

# is_next(io::IO, ::Type{T}) where {T <: Declaration} = peek_str(io, 2) == "<?" && peek_str(io, 5) == "<?xml"


# #-----------------------------------------------------------------------------# Element
# """
#     Element(name, children...; attributes)
#     # <name attributes...> children... </name>
# """
# struct Element{T} <: XMLNode
#     name::T
#     attributes::Vector{Pair{T, T}}
#     children::Vector{Union{Element{T}, Text{T}, CData{T}, Comment{T}}}
# end
# function write_xml(io::IO, o::Element)
#     print(io, '<', o.name)
#     for x in o.attributes
#         print(io, ' ', x[1], '=', repr(x[2]))
#     end
#     print(io, '>')
#     for x in o.children
#         write_xml(io, x)
#     end
#     print(io, "</", o.name, '>')
# end
# function read_xml(io::IO, ::Type{T}) where {T <: Element}
#     read(io, 1)
#     readuntil(io, )
# end
# function is_next(io::IO, ::Type{T}) where {T <: Element}
#     a, b = peek_str(io)
#     a == '<' && is_name_start_char(b)
# end

# #-----------------------------------------------------------------------------# DTD
# """
#     DTD(value)
#     # <!DOCTYPE
# """
# struct DTD{T} <: XMLNode
#     value::T
# end

# #-----------------------------------------------------------------------------# Document
# struct Document{T} <: XMLNode
#     prolog::Vector{Union{ProcessingInstruction{T}, DTD{T},  Declaration{T}, Comment{T}}}
#     root::Element{T}
# end

# #-----------------------------------------------------------------------------# Fragment
# struct Fragment{T} <: XMLNode
#     children::Vector{Union{Element{T}, Comment{T}, CData{T}, Text{T}}}
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
