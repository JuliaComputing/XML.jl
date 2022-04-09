module XML

using OrderedCollections: OrderedDict
using AbstractTrees
using Tokenize: tokenize

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
    depth::Int = -1
end

function show_xml(io::IO, o::Node)
    if o.nodetype == DOCUMENT
        foreach(x -> show_xml(io, x), o.children)
    else
        print_opening_tag(io, o)
        foreach(x -> show_xml(io, x), o.children)
        print_closing_tag(io, o)
    end
end

function Base.:(==)(a::Node, b::Node)
    a.nodetype == b.nodetype &&
        a.tag == b.tag &&
        a.attributes == b.attributes &&
        all(a.children .== b.children) &&
        a.content == b.content
end

Base.write(io::IO, o::Node) = show(io, MIME"application/xml"(), o)
Base.write(file::AbstractString, o::Node) = open(io -> write(io, o), touch(file), "w")

function print_opening_tag(io::IO, o::Node)
    if o.nodetype == DOCTYPE
        print(io, "<!DOCTYPE ", o.content, '>')
    elseif o.nodetype == DECLARATION
        print(io, "<?", o.tag); print_attrs(io, o); print(io, "?>")
    elseif o.nodetype == COMMENT
        print(io, "<!-- ", o.content, " -->")
    elseif o.nodetype == CDATA
        print(io, "<![CDATA[", o.content, "]]>")
    elseif o.nodetype == ELEMENT
        print(io, '<', o.tag); print_attrs(io, o); print(io, '>')
    elseif o.nodetype == ELEMENTSELFCLOSED
        print(io, '<', o.tag); print_attrs(io, o); print(io, "/>")
    elseif o.nodetype == TEXT
        print(io, o.content)
    end
end

function print_closing_tag(io::IO, o::Node)
    if o.nodetype == ELEMENT
        print(io, "</", o.tag, '>')
    end
end

Base.getindex(o::Node, i::Integer) = o.children[i]
Base.lastindex(o::Node) = lastindex(o.children)

root(node::Node) = node.nodetype == DOCUMENT ? node.children[end] : error("Only Document Nodes have a root element.")

#-----------------------------------------------------------------------------# Node show
Base.show(io::IO, ::MIME"text/plain", o::Node) = AbstractTrees.print_tree(io, o)
Base.show(io::IO, ::MIME"application/xml", o::Node) = show_xml(io, o)
Base.show(io::IO, ::MIME"text/xml", o::Node) = show_xml(io, o)


function AbstractTrees.printnode(io::IO, o::Node)
    print(io, o.nodetype)
    print(io, "  ")
    print_opening_tag(io, o)
end

AbstractTrees.children(o::Node) = o.children

print_attrs(io::IO, o::Node) = print(io, (" $k=$(repr(v))" for (k,v) in o.attributes)...)


#-----------------------------------------------------------------------------# EachNodeString
# Iterator that returns one of the following (as a String):
#   <?xml ...>
#   <!doctype ...>
#   <tag ...>
#   <tag .../>
#   text
#   <!-- ... -->
#   <![CDATA[...]]>
struct EachNodeString{IOT <: IO}
    io::IOT
    buffer::IOBuffer  # TODO: use this
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
function Node(o::EachNodeString; debug=false)
    out = Node(nodetype=DOCUMENT)
    add_children!(out, o; until="NEVER", depth=0, debug)
    out
end

# parse siblings until the `until` String is returned by the iterator (e.g. `</NAME>`)
function add_children!(out::Node, o::EachNodeString; until::String, depth::Integer, debug=false)
    s = ""
    while s != until
        next = iterate(o)
        isnothing(next) && break
        s = next[1]
        node = if debug
            try
                init_node_parse(s)
            catch
                error(s)
            end
        else
            init_node_parse(s)
        end
        isnothing(node) && continue
        node.depth = depth
        if node.nodetype == ELEMENT
            add_children!(node, o; until="</$(node.tag)>", depth=depth+1, debug)
        end
        push!(out.children, node)
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
function document(file::AbstractString; debug=false)
    open(file, "r") do io
        itr = EachNodeString(io)
        Node(itr; debug)
    end
end



end
