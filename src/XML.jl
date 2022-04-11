module XML

using OrderedCollections: OrderedDict
using AbstractTrees
using Dates

#-----------------------------------------------------------------------------# escape/unescape
escape_chars = ['&' => "&amp;", '"' => "&quot;", ''' => "&#39;", '<' => "&lt;", '>' => "&gt;"]
escape(x::AbstractString) = replace(x, escape_chars...)
unescape(x::AbstractString) = replace(x, reverse.(escape_chars)...)


#-----------------------------------------------------------------------------# Node
@enum NodeType DOCUMENT DOCTYPE DECLARATION COMMENT CDATA ELEMENT ELEMENTSELFCLOSED TEXT

Base.@kwdef mutable struct Node
    nodetype::NodeType
    tag::String = ""
    attributes::OrderedDict{String, String} = OrderedDict{String,String}()
    children::Vector{Node} = Node[]
    content::String = ""
end

Base.getindex(o::Node, i::Integer) = children(o)[i]
Base.lastindex(o::Node) = lastindex(children(o))
Base.setindex!(o::Node, val::Node, i::Integer) = setindex!(children(o), val, i)

Base.getproperty(o::Node, x::Symbol) = attributes(o)[string(x)]
Base.setproperty!(o::Node, x::Union{AbstractString,Symbol}, val::Union{AbstractString,Symbol}) = (attributes(o)[string(x)] = string(val))

nchildren(o::Node) = length(children(o))

for field in (:nodetype, :tag, :attributes, :children, :content)
    @eval $field(o::Node) = getfield(o, $(QuoteNode(field)))
end


function show_xml(io::IO, o::Node)
    if nodetype(o) == DOCUMENT
        foreach(x -> show_xml(io, x), children(o))
    else
        print_opening_tag(io, o)
        foreach(x -> show_xml(io, x), children(o))
        print_closing_tag(io, o)
    end
end

function Base.:(==)(a::Node, b::Node)
    nodetype(a) == nodetype(b) &&
        tag(a) == tag(b) &&
        attributes(a) == attributes(b) &&
        all(children(a) .== children(b)) &&
        content(a) == content(b)
end

Base.write(io::IO, o::Node) = show(io, MIME"application/xml"(), o)
Base.write(file::AbstractString, o::Node) = open(io -> write(io, o), touch(file), "w")

function print_opening_tag(io::IO, o::Node)
    if nodetype(o) == DOCTYPE
        print(io, "<!DOCTYPE ", content(o), '>')
    elseif nodetype(o) == DECLARATION
        print(io, "<?", tag(o)); print_attrs(io, o); print(io, "?>")
    elseif nodetype(o) == COMMENT
        print(io, "<!-- ", content(o), " -->")
    elseif nodetype(o) == CDATA
        print(io, "<![CDATA[", content(o), "]]>")
    elseif nodetype(o) == ELEMENT
        print(io, '<', tag(o)); print_attrs(io, o); print(io, '>')
    elseif nodetype(o) == ELEMENTSELFCLOSED
        print(io, '<', tag(o)); print_attrs(io, o); print(io, "/>")
    elseif nodetype(o) == TEXT
        print(io, content(o))
    end
end

function print_closing_tag(io::IO, o::Node)
    if nodetype(o) == ELEMENT
        print(io, "</", tag(o), '>')
    end
end

print_attrs(io::IO, o::Node) = print(io, (" $k=$(repr(v))" for (k,v) in attributes(o))...)

root(o::Node) = nodetype(o) == DOCUMENT ? children(o)[end] : error("Only Document Nodes have a root element.")





#-----------------------------------------------------------------------------# Node show
Base.show(io::IO, ::MIME"text/plain", o::Node) = AbstractTrees.print_tree(io, o)
Base.show(io::IO, ::MIME"application/xml", o::Node) = show_xml(io, o)
Base.show(io::IO, ::MIME"text/xml", o::Node) = show_xml(io, o)

#-----------------------------------------------------------------------------# AbstractTrees
function AbstractTrees.printnode(io::IO, o::Node)
    print_opening_tag(io, o)
    print(io, " (", nchildren(o), ')')
end

AbstractTrees.children(o::Node) = children(o)

AbstractTrees.nodetype(::Node) = Node




#-----------------------------------------------------------------------------# EachNodeString
# Iterator that returns one of the following (as a String):
#   <?xml ...>
#   <!doctype ...>
#   <tag ...>
#   </tag>
#   <tag .../>
#   text
#   <!-- ... -->
#   <![CDATA[...]]>
struct EachNodeString{IOT <: IO}
    io::IOT
    buffer::IOBuffer  # TODO: use this?
end
EachNodeString(io::IO) = EachNodeString(io, IOBuffer())

function readchar(o::EachNodeString)
    c = peek(o.io, Char)
    write(o.buffer, c)
    c
end

function Base.iterate(o::EachNodeString, state=nothing)
    io = o.io
    skipchars(isspace, io)
    eof(io) && return nothing
    c = readchar(o)

    s = if c === '<'
        s = readuntil(io, '>')
        if startswith(s, "<!--")
            while !occursin("--", s)
                s *= readuntil(io, '>')
            end
        elseif startswith(s, "<![CDATA")
            while !occursin("]]", s)
                s *= readuntil(io, '>')
            end
        end
        s * '>'
    else
        s = rstrip(readuntil(io, '<'))
        skip(io, -1)
        s
    end
    (s, nothing)
end

Base.eltype(::Type{<:EachNodeString}) = String

Base.IteratorSize(::Type{<:EachNodeString}) = Base.SizeUnknown()

Base.isdone(itr::EachNodeString, state...) = eof(itr.io)

#-----------------------------------------------------------------------------# Node from EachNodeString
function Node(o::EachNodeString)
    out = Node(nodetype=DOCUMENT)
    add_children!(out, o; until="FOREVER")
    out
end

# parse siblings until the `until` String is returned by the iterator (e.g. `</NAME>`)
function add_children!(out::Node, o::EachNodeString; until::String)
    s = ""
    while s != until
        next = iterate(o)
        isnothing(next) && break
        s = next[1]
        node = init_node_parse(s)
        isnothing(node) && continue
        if nodetype(node) == ELEMENT
            add_children!(node, o; until="</$(tag(node))>")
        end
        push!(children(out), node)
    end
end

# Initialize the node (before `add_children!` gets run).
function init_node_parse(s::AbstractString)
    if startswith(s, "<?xml")
        Node(nodetype=DECLARATION, tag=get_tag(s), attributes=get_attrs(s))
    elseif startswith(s, "<!DOCTYPE") || startswith(s, "<!doctype")
        Node(nodetype=DOCTYPE, content=s)
    elseif startswith(s, "<![CDATA")
        Node(nodetype=CDATA, content=replace(s, "<![CDATA[" => "", "]]>" => ""))
    elseif startswith(s, "<!--")
        Node(nodetype=COMMENT, content=replace(s, "<!-- " => "", " -->" => ""))
    elseif startswith(s, "<") && endswith(s, "/>")
        Node(nodetype=ELEMENTSELFCLOSED, tag=get_tag(s), attributes=get_attrs(s))
    elseif startswith(s, "</")
        nothing
    elseif startswith(s, "<")
        Node(nodetype=ELEMENT, tag=get_tag(s), attributes=get_attrs(s))
    else
        Node(nodetype=TEXT, content=s)
    end
end

get_tag(x) = x[findfirst(r"[a-zA-z][^\s>/]*", x)]  # Matches: (any letter) → (' ', '/', '>')

function get_attrs(x)
    out = OrderedDict{String,String}()
    rng = findfirst(r"(?<=\s).*\"", x)
    isnothing(rng) && return out
    s = x[rng]
    kys = (m.match for m in eachmatch(r"[a-zA-Z][a-zA-Z\.-_]*(?=\=)", s))
    vals = (m.match for m in eachmatch(r"(?<=(\=\"))[^\"]*", s))
    foreach(zip(kys,vals)) do (k,v)
        out[k] = v
    end
    out
end


#-----------------------------------------------------------------------------# document
function document(file::AbstractString)
    open(file, "r") do io
        itr = EachNodeString(io)
        Node(itr)
    end
end

end
