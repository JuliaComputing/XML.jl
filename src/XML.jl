module XML

using OrderedCollections: OrderedDict
using Mmap
using Tables
import AbstractTrees: AbstractTrees, children, parent

export Node, RowNode,
    children, parent, nodetype, tag, attributes, value, depth, next, prev

#-----------------------------------------------------------------------------# escape/unescape
# This is only used within TEXT nodes, so we ignore ''' and '"'
const escape_chars = ('&' => "&amp;", '<' => "&lt;", '>' => "&gt;")
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

#-----------------------------------------------------------------------------# RawDataType
"""
    RawDataType:
    - RAW_TEXT                    # text
    - RAW_COMMENT                 # <!-- ... -->
    - RAW_CDATA                   # <![CDATA[...]]>
    - RAW_DECLARATION             # <?xml attributes... ?>
    - RAW_PROCESSING_INSTRUCTION  # <?NAME attributes... ?>
    - RAW_DTD                     # <!DOCTYPE ...>
    - RAW_ELEMENT_OPEN            # <NAME attributes... >
    - RAW_ELEMENT_CLOSE           # </NAME>
    - RAW_ELEMENT_SELF_CLOSED     # <NAME attributes... />
    - RAW_DOCUMENT                # Something to initilize with (not really used)
"""
@enum(RawDataType, RAW_DOCUMENT, RAW_TEXT, RAW_COMMENT, RAW_CDATA, RAW_PROCESSING_INSTRUCTION,
    RAW_DECLARATION, RAW_DTD, RAW_ELEMENT_OPEN, RAW_ELEMENT_CLOSE, RAW_ELEMENT_SELF_CLOSED)

nodetype(x::RawDataType) =
    x === RAW_ELEMENT_OPEN              ? ELEMENT :
    x === RAW_ELEMENT_CLOSE             ? ELEMENT :
    x === RAW_ELEMENT_SELF_CLOSED       ? ELEMENT :
    x === RAW_TEXT                      ? TEXT :
    x === RAW_COMMENT                   ? COMMENT :
    x === RAW_CDATA                     ? CDATA :
    x === RAW_DECLARATION               ? DECLARATION :
    x === RAW_DTD                       ? DTD :
    x === RAW_PROCESSING_INSTRUCTION    ? PROCESSING_INSTRUCTION :
    x === RAW_DOCUMENT                  ? DOCUMENT :
    nothing

#-----------------------------------------------------------------------------# RawData
"""
    RawData(filename::String)

Create an iterator over raw chunks of data in an XML file.  Each chunk of data represents one of:

    - RAW_DOCUMENT                # Only used to initialize the iterator state.
    - RAW_TEXT                    # text
    - RAW_COMMENT                 # <!-- ... -->
    - RAW_CDATA                   # <![CDATA[...]]>
    - RAW_DECLARATION             # <?xml attributes... ?>
    - RAW_PROCESSING_INSTRUCTION  # <?NAME attributes... ?>
    - RAW_DTD                     # <!DOCTYPE ...>
    - RAW_ELEMENT_OPEN            # <NAME attributes... >
    - RAW_ELEMENT_CLOSE           # </NAME>
    - RAW_ELEMENT_SELF_CLOSED     # <NAME attributes... />

Useful functions:

    - view(o::RawData) --> view of the Vector{UInt8} chunk.
    - String(o::RawData) --> String of the chunk.
    - next(o::RawData) --> RawData of the next chunk (or `nothing`).
    - prev(o::RawData) --> RawData of the previous chunk (or `nothing`).
    - tag(o::RawData) --> String of the tag name (or `nothing`).
    - attributes(o::RawData) --> OrderedDict{String, String} of the attributes (or `nothing`).
    - value(o::RawData) --> String of the value (or `nothing`).
    - children(o::RawData) --> Vector{RawData} of the children (or `nothing`).
    - parent(o::RawData) --> RawData of the parent (or `nothing`)
    - depth(o::RawData) --> Int of the depth of the node in the XML DOM.
"""
struct RawData
    type::RawDataType
    depth::Int
    pos::Int
    len::Int
    data::Vector{UInt8}
end
RawData(data::Vector{UInt8}) = RawData(RAW_DOCUMENT, 0, 0, 0, data)
RawData(filename::String) = RawData(Mmap.mmap(filename))

parse(x::AbstractString, ::Type{RawData}) = RawData(Vector{UInt8}(x))

Tables.rows(o::RawData) = o
Tables.schema(o::RawData) = Tables.Schema(fieldnames(RawData)[1:end-1], fieldtypes(RawData)[1:end-1])

function Base.show(io::IO, o::RawData)
    print(io, o.depth, ": ", o.type, " (pos=", o.pos, ", len=", o.len, ")")
    o.len > 0 && printstyled(io, ": ", String(o.data[o.pos:o.pos + o.len]); color=:light_green)
end
function Base.:(==)(a::RawData, b::RawData)
    a.type == b.type && a.depth == b.depth && a.pos == b.pos && a.len == b.len && a.data === b.data
end

Base.view(o::RawData) = view(o.data, o.pos:o.pos + o.len)
String(o::RawData) = String(view(o))

Base.IteratorSize(::Type{RawData}) = Base.SizeUnknown()
Base.eltype(::Type{RawData}) = RawData

function Base.iterate(o::RawData, state=o)
    n = next(state)
    return isnothing(n) ? nothing : (n, n)
end

is_node(o::RawData) = o.type !== RAW_ELEMENT_CLOSE
nodes(o::RawData) = Iterators.Filter(is_node, o)

#-----------------------------------------------------------------------------# get_name
# find the start/stop of a name given a starting position `i`
_name_start(data, i) = findnext(x -> isletter(Char(x)) || Char(x) === '_', data, i)
is_name_char(x) = (c = Char(x); isletter(c) || isdigit(c) || c ∈ "._-:")
function _name_stop(data, i)
    i = findnext(!is_name_char, data, i)
    isnothing(i) ? length(data) : i
end

# starting at position i, return name and position after name
function get_name(data, i)
    i = _name_start(data, i)
    j = _name_stop(data, i)
    name = String(data[i:j-1])
    return name, j
end

#-----------------------------------------------------------------------------# get_attributes
# starting at position i, return attributes up until the next '>' or '?' (DTD)
function get_attributes(data, i)
    j = findnext(x -> x == UInt8('>') || x == UInt8('?'), data, i)
    i = _name_start(data, i)
    i > j && return nothing
    out = OrderedDict{String, String}()
    while !isnothing(i) && i < j
        key, i = get_name(data, i)
        # get quotechar the value is wrapped in (either ' or ")
        i = findnext(x -> Char(x) === '"' || Char(x) === ''', data, i)
        quotechar = data[i]
        i2 = findnext(==(quotechar), data, i + 1)
        value = String(data[i+1:i2-1])
        out[key] = value
        i = _name_start(data, i2)
    end
    return out
end

#-----------------------------------------------------------------------------# interface
nodetype(o::RawData) = nodetype(o.type)

function tag(o::RawData)
    o.type ∉ [RAW_ELEMENT_OPEN, RAW_ELEMENT_CLOSE, RAW_ELEMENT_SELF_CLOSED, RAW_PROCESSING_INSTRUCTION] && return nothing
    return get_name(o.data, o.pos + 1)[1]
end

function attributes(o::RawData)
    if o.type === RAW_ELEMENT_OPEN || o.type === RAW_ELEMENT_SELF_CLOSED || o.type === RAW_PROCESSING_INSTRUCTION
        i = o.pos
        i = _name_start(o.data, i)
        i = _name_stop(o.data, i)
        get_attributes(o.data, i)
    elseif o.type === RAW_DECLARATION
        get_attributes(o.data, o.pos + 6)
    else
        nothing
    end
end

function value(o::RawData)
    if o.type === RAW_TEXT
        String(o)
    elseif o.type === RAW_CDATA
        String(view(o.data, o.pos + length("<![CDATA[") : o.pos + o.len - 3))
    elseif o.type === RAW_COMMENT
        String(view(o.data, o.pos + length("<!--") : o.pos + o.len - 3))
    elseif o.type === RAW_DTD
        String(view(o.data, o.pos + length("<!DOCTYPE ") : o.pos + o.len - 1))
    else
        nothing
    end
end

function children(o::RawData)
    if o.type === RAW_ELEMENT_OPEN || o.type === RAW_DOCUMENT
        depth = o.depth
        out = RawData[]
        for item in o
            item.type === RAW_ELEMENT_CLOSE && continue  # skip closing tags
            item.depth == depth + 1 && push!(out, item)
            item.depth == depth && break
            o.type === RAW_DOCUMENT && item.depth == 2 && break # break if we've seen the doc root
        end
        out
    else
        RawData[]
    end
end

function parent(o::RawData)
    depth = o.depth
    depth === 1 && return nothing
    p = prev(o)
    while p.depth >= depth
        p = prev(p)
    end
    return p
end

depth(o::RawData) = o.depth

#-----------------------------------------------------------------------------# next RawData
notspace(x::UInt8) = !isspace(Char(x))

function next(o::RawData)
    i = o.pos + o.len + 1
    (; depth, data, type) = o
    try
        i = findnext(notspace, data, i)  # skip insignificant whitespace
    catch
        @info String(o)
        error()
    end
    isnothing(i) && return nothing
    if type === RAW_ELEMENT_OPEN || type === RAW_DOCUMENT
        depth += 1
    end
    c = Char(o.data[i])
    j = i + 1
    if c !== '<'
        type = RAW_TEXT
        j = findnext(==(UInt8('<')), data, i) - 1
        j = findprev(notspace, data, j)   # "rstrip"
    elseif c === '<'
        c2 = Char(o.data[i + 1])
        if c2 === '!'
            c3 = Char(o.data[i + 2])
            if c3 === '-'
                type = RAW_COMMENT
                j = findnext(Vector{UInt8}("-->"), data, i)[end]
            elseif c3 === '['
                type = RAW_CDATA
                j = findnext(Vector{UInt8}("]]>"), data, i)[end]
            elseif c3 === 'D'
                type = RAW_DTD
                j = findnext(x -> x == UInt8('>'), data, i)
            else
                error("Should be unreachable.  Unexpected typeen: $c$c2$c3")
            end
        elseif c2 === '?'
            if get_name(data, i + 2)[1] == "xml"
                type = RAW_DECLARATION
            else
                type = RAW_PROCESSING_INSTRUCTION
            end
            j = findnext(Vector{UInt8}("?>"), data, i)[end]
        elseif c2 === '/'
            type = RAW_ELEMENT_CLOSE
            depth -= 1
            j = findnext(==(UInt8('>')), data, i)
        else
            j = findnext(==(UInt8('>')), data, i)
            if data[j-1] === UInt8('/')
                type = RAW_ELEMENT_SELF_CLOSED
            else
                type = RAW_ELEMENT_OPEN
            end
        end
    end
    return RawData(type, depth, i, j - i, data)
end

#-----------------------------------------------------------------------------# prev RawData
function prev(o::RawData)
    (; depth, data, type) = o
    type === RAW_DOCUMENT && return nothing
    j = o.pos - 1
    j = findprev(notspace, data, j)  # skip insignificant whitespace
    isnothing(j) && return RawData(data)  # RAW_DOCUMENT
    c = Char(o.data[j])
    i = j - 1
    next_type = type
    if c !== '>' # text
        type = RAW_TEXT
        i = findprev(==(UInt8('>')), data, j) + 1
        i = findnext(notspace, data, i)  # "lstrip"
    elseif c === '>'
        c2 = Char(o.data[j - 1])
        if c2 === '-'
            type = RAW_COMMENT
            i = findprev(Vector{UInt8}("<--"), data, j)[1]
        elseif c2 === ']'
            type = RAW_CDATA
            i = findprev(Vector{UInt8}("<![CDATA["), data, j)[1]
        elseif c2 === '?'
            i = findprev(Vector{UInt8}("<?"), data, j)[1]
            if get_name(data, i + 2)[1] == "xml"
                type = RAW_DECLARATION
            else
                type = RAW_PROCESSING_INSTRUCTION
            end
        else
            i = findprev(==(UInt8('<')), data, j)
            char = Char(data[i+1])
            if char === '/'
                type = RAW_ELEMENT_CLOSE
            elseif char === '!'
                type = DTD
            elseif isletter(char) || char === '_'
                type = Char(o.data[j - 2]) === '/' ? RAW_ELEMENT_SELF_CLOSED : RAW_ELEMENT_OPEN
            else
                error("Should be unreachable.  Unexpected data: <$char ... $c3$c2$c1>.")
            end
        end
    else
        error("Unreachable reached in XML.prev")
    end
    if type !== RAW_ELEMENT_OPEN && next_type === RAW_ELEMENT_CLOSE
        depth += 1
    elseif type == RAW_ELEMENT_OPEN && next_type !== RAW_ELEMENT_CLOSE
        depth -= 1
    end
    return RawData(type, depth, i, j - i, data)
end


#-----------------------------------------------------------------------------# RowNode
"""
    RowNode(file::AbstractString)
    RowNode(data::XML.RawData)

An XML node that is lazy only in how it accesses its children (available via `children(::RowNode)`).

`RowNode` also satisfies the `Tables.rowaccess` interface for loading an XML file as
a tabular dataset, e.g.

    using XML, DataFrames
    df = DataFrame(RowNode("file.xml"))
"""
struct RowNode
    nodetype::NodeType
    tag::Union{String, Nothing}
    attributes::Union{OrderedDict{String, String}, Nothing}
    value::Union{String, Nothing}
    data::RawData
end
function RowNode(data::RawData)
    nodetype = XML.nodetype(data.type)
    tag = XML.tag(data)
    attributes = XML.attributes(data)
    value = XML.value(data)
    RowNode(nodetype, tag, attributes, value, data)
end
RowNode(file::AbstractString) = RowNode(RawData(file))

Base.parse(x::AbstractString, ::Type{RowNode}) = RowNode(parse(x, RawData))

function Base.getproperty(o::RowNode, x::Symbol)
    x === :depth && return getfield(o, :data).depth
    x === :nodetype && return getfield(o, :nodetype)
    x === :tag && return getfield(o, :tag)
    x === :attributes && return getfield(o, :attributes)
    x === :value && return getfield(o, :value)
    error("XML.RowNode does not have property: $x.")
end

Base.propertynames(o::RowNode) = (:depth, :nodetype, :tag, :attributes, :value)

Tables.rows(o::RowNode) = o
Tables.schema(o::RowNode) = Tables.Schema(
    (:depth, :nodetype, :tag, :attributes, :value),
    (Int, NodeType, Union{Nothing, String}, Union{Nothing, OrderedDict{String, String}}, Union{Nothing, String}),
)

children(o::RowNode) = RowNode.(children(getfield(o, :data)))
tag(o::RowNode) = o.tag
attributes(o::RowNode) = o.attributes
value(o::RowNode) = o.type === TEXT ? escape(o.value) : o.value
nodetype(o::RowNode) = o.nodetype
depth(o::RowNode) = o.depth
parent(o::RowNode) = RowNode(parent(getfield(o, :data)))

Base.show(io::IO, o::RowNode) = _show_node(io, o)

Base.IteratorSize(::Type{RowNode}) = Base.SizeUnknown()
Base.eltype(::Type{RowNode}) = RowNode

function Base.iterate(o::RowNode, state = getfield(o, :data))
    n = next(state)
    isnothing(n) && return nothing
    n.type === RAW_ELEMENT_CLOSE && return iterate(o, n)
    return RowNode(n), n
end

function next(o::RowNode)
    n = next(getfield(o, :data))
    isnothing(n) && return nothing
    n.type === RAW_ELEMENT_CLOSE && return next(RowNode(n))
    return RowNode(n)
end
function prev(o::RowNode)
    n = prev(getfield(o, :data))
    isnothing(n) && return nothing
    n.type === RAW_ELEMENT_CLOSE && return prev(RowNode(n))
    return RowNode(n)
end

#-----------------------------------------------------------------------------# Node
Base.@kwdef struct Node
    nodetype::NodeType
    tag::Union{Nothing, String} = nothing
    attributes::Union{Nothing, OrderedDict{String, String}} = nothing
    value::Union{Nothing, String} = nothing
    children::Union{Nothing, Vector{Node}} = nothing
    depth::Int = 0
end
Node(nodetype; kw...) = Node(; nodetype, kw...)
Node(file::AbstractString) = Node(RawData(file))
Node(data::RawData) = Node(RowNode(data))

function Node(node::RowNode)
    o = Node(node.nodetype, node.tag, node.attributes, node.value, nothing, node.depth)
    children = XML.children(node)
    if !isempty(children)
        o = Node(o; children=Node[])
        for child in children
            push!(o, Node(child))
        end
    end
    return o
end

Base.parse(x::AbstractString, ::Type{Node}) = Node(parse(x, RawData))

function Node((;nodetype, tag, attributes, value, children, depth)::Node; kw...)
    Node(; nodetype, tag, attributes, value, children, depth, kw...)
end
function (o::Node)(children...)
    isempty(children) && return o
    out = sizehint!(Node[], length(children))
    foreach(children) do x
        if x isa Node
            push!(out, Node(x; depth=o.depth + 1))
        else
            push!(out, Node(nodetype=TEXT_NODE, value=string(x), depth=o.depth + 1))
        end
    end

    Node(o; children=out)
end

function _nodes_equal(a, b)
    out = XML.tag(a) == XML.tag(b)
    out &= XML.nodetype(a) == XML.nodetype(b)
    out &= XML.attributes(a) == XML.attributes(b)
    out &= XML.value(a) == XML.value(b)
    out &= length(XML.children(a)) == length(XML.children(b))
    out &= all(_nodes_equal(ai, bi) for (ai,bi) in zip(XML.children(a), XML.children(b)))
    return out
end

Base.:(==)(a::Node, b::Node) = _nodes_equal(a, b)

Base.getindex(o::Node, i::Integer) = o.children[i]
Base.setindex!(o::Node, val, i::Integer) = o.children[i] = Node(val)
Base.lastindex(o::Node) = lastindex(o.children)

Base.push!(a::Node, b::Node) = push!(a.children, b)

children(o::Node) = isnothing(o.children) ? Node[] : o.children
tag(o::Node) = o.tag
attributes(o::Node) = o.attributes
value(o::Node) = o.value
nodetype(o::Node) = o.nodetype
depth(o::Node) = o.depth
parent(o::Node) = nothing  # Nodes only keep track of their children

Base.show(io::IO, o::Node) = _show_node(io, o)


# #-----------------------------------------------------------------------------# printing
function _show_node(io::IO, o)
    printstyled(io, typeof(o), ' '; color=:light_black)
    printstyled(io, nodetype(o), ; color=:light_green)
    if o.nodetype === TEXT
        printstyled(io, repr(value(o)))
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
        printstyled(io, '>', color=:light_cyan)
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
function _print_n_children(io::IO, o)
    children = AbstractTrees.children(o)
    n = ismissing(children) || isnothing(children) ? 0 : length(children)
    text = n == 0 ? "" : n == 1 ? " (1 child)" : " ($(length(children)) children)"
    printstyled(io, text, color=:light_black)
end

#-----------------------------------------------------------------------------# write_xml
write(x) = (io = IOBuffer(); write(io, x); String(take!(io)))

write(filename::AbstractString, x) = open(io -> write(io, x), filename, "w")

function write(io::IO, x; indent = "   ")
    nodetype = XML.nodetype(x)
    tag = XML.tag(x)
    value = XML.value(x)
    children = XML.children(x)
    depth = XML.depth(x)

    padding = indent ^ max(0, depth - 1)
    print(io, padding)
    if nodetype === TEXT
        print(io, unescape(value))
    elseif nodetype === ELEMENT
        print(io, '<', tag)
        _print_attrs(io, x)
        print(io, isnothing(children) ? '/' : "", '>')
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
    elseif nodetype === COMMENT
        print(io, "<!--", value, "-->")
    elseif nodetype === CDATA
        print(io, "<![CDATA[", value, "]]>")
    elseif nodetype === DOCUMENT
        foreach(AbstractTrees.children(x)) do child
            write(io, child; indent)
            println(io)
        end
    else
        error("Unreachable case reached during XML.write")
    end
end

end
