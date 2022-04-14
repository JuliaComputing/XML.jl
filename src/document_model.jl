abstract type AbstractXMLNode end

# AbstractTrees.children(::AbstractXMLNode) = ()
# AbstractTrees.printnode(io::IO, o::T) where {T<:AbstractXMLNode} = print(io, T)


#-----------------------------------------------------------------------------# pretty printing
const INDENT = "    "

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
# TODO: all the messy details of DTD.  For now, just dump everything into `text`
struct DTD <: AbstractXMLNode
    text::String
end
Base.show(io::IO, o::DTD) = print(io, "<!DOCTYPE ", o.text, '>')


#-----------------------------------------------------------------------------# Declaration
mutable struct Declaration <: AbstractXMLNode
    tag::String
    attributes::OrderedDict{Symbol, String}
end
Base.show(io::IO, o::Declaration) = (print(io, "<!", o.tag); print_attributes(io, o); print(io, '>'))
attributes(o::Declaration) = o.attributes

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
Element() = Element("JUNK", OrderedDict{Symbol,String}(), Union{CData, Comment, Element, String}[])
function Base.show(io::IO, o::Element)
    print(io, '<', tag(o))
    print_attributes(io, o)
    if isempty(children(o))
        print(io, "/>")
    else
        print(io, "> (", length(children(o)), " children)")
    end
end
function print_attributes(io::IO, o::AbstractXMLNode)
    foreach(pairs(attributes(o))) do (k,v)
        print(io, ' ', k, '=', '"', v, '"')
    end
end

AbstractTrees.children(o::Element) = getfield(o, :children)
tag(o::Element) = getfield(o, :tag)
attributes(o::Element) = getfield(o, :attributes)

Base.getindex(o::Element, i::Integer) = children(o)[i]
Base.lastindex(o::Element) = lastindex(children(o))
Base.setindex!(o::Element, val::Element, i::Integer) = setindex!(children(o), val, i)

Base.getproperty(o::Element, x::Symbol) = attributes(o)[string(x)]
Base.setproperty!(o::Element, x::Union{AbstractString,Symbol}, val::Union{AbstractString,Symbol}) = (attributes(o)[string(x)] = string(val))



#-----------------------------------------------------------------------------# Document
mutable struct Document
    prolog::Vector{Union{Comment, Declaration, DTD}}
    root::Element
end
Document() = Document(Union{Comment,Declaration,DTD}[], Element())

Base.show(io::IO, o::Document) = AbstractTrees.print_tree(io, o)
AbstractTrees.printnode(io::IO, o::Document) = print(io, "XML.Document")

AbstractTrees.children(o::Document) = (o.prolog..., o.root)
