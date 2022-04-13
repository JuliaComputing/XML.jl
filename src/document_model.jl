abstract type AbstractXMLNode end

#-----------------------------------------------------------------------------# pretty printing
indent = "    "

function pretty(x, depth=0)
    io = IOBuffer()
    pretty(io, x, depth)
    println(String(take!(io)))
end

pretty(io::IO, o::AbstractXMLNode, depth=0) = println(io, indent ^ depth, o)

function pretty(io::IO, o::String, depth=0)
    whitespace = indent ^ depth
    for line in split(o; keepempty=false)
        while !startswith(line, whitespace)
            line = ' ' * line
        end
        println(io, line)
    end
end

#-----------------------------------------------------------------------------# DTD
# TODO: all the messy details of DTD
struct DTD <: AbstractXMLNode
    text::String
end
Base.show(io::IO, o::DTD) = print(io, "<!DOCTYPE ", o.text, '>')

#-----------------------------------------------------------------------------# Declaration
mutable struct Declaration <: AbstractXMLNode
    tag::String
    attributes::OrderedDict{Symbol, String}
end
function Base.show(io::IO, o::Declaration)
    print(io, "<!", o.tag)
    print_attrs(io, o)
    print(io, '>')
end

#-----------------------------------------------------------------------------# CData
mutable struct CData <: AbstractXMLNode
    text::String
end
Base.show(io::IO, o::CData) = print(io, "<![CDATA[", o.text, "]]>")

#-----------------------------------------------------------------------------# Comment
mutable struct Comment <: AbstractXMLNode
    text::String
end
Base.show(io::IO, o::Comment) = print(io, "<!-- ", o.text, " -->")

#-----------------------------------------------------------------------------# Element
mutable struct Element <: AbstractXMLNode
    tag::String
    attributes::OrderedDict{Symbol, String}
    children::Vector{Union{CData, Comment, Element, String}}
end
function Element(tag::String, children...; kw...)
    Element(tag, OrderedDict(k => string(v) for (k,v) in pairs(kw)), collect(children))
end
function Base.show(io::IO, o::Element)
    print(io, '<', o.tag)
    print_attributes(io, o)
    print(io, '>')
    foreach(x -> show(io, x), o.children)
    print(io, "</", o.tag, '>')
end
function pretty(io::IO, o::Element, depth=0)
    print(io, '<', o.tag)
    print_atributes(io, o)
    println(io, '>')
    foreach(x -> pretty(io, x, depth + 1), o.children)
    println(io, "</", o.tag, '>')
end
print_attributes(io::IO, o::AbstractXMLNode) = foreach(pairs(o.attributes)) do (k,v)
    print(io, ' ', k, '=', '"', v, '"')
end

#-----------------------------------------------------------------------------# Document
mutable struct Document
    prolog::Vector{Union{Comment, Declaration, DTD}}
    root::Element
end
function Base.show(io::IO, o::Document)
    foreach(x -> show(io, x), o.prolog)
    show(io, o.root)
end
function pretty(io::IO, o::Document)
    foreach(x -> pretty(io, x), o.prolog)
    pretty(io, o.root)
end
