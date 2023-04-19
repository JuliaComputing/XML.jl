module XML

using OrderedCollections: OrderedDict
using Mmap
using Tables
import AbstractTrees: AbstractTrees, children

export Node, NodeType, children

#-----------------------------------------------------------------------------# escape/unescape
escape_chars = ['&' => "&amp;", '"' => "&quot;", ''' => "&#39;", '<' => "&lt;", '>' => "&gt;"]
escape(x::AbstractString) = replace(x, escape_chars...)
unescape(x::AbstractString) = replace(x, reverse.(escape_chars)...)

#-----------------------------------------------------------------------------# NodeType
"""
    NodeType:
    - DOCUMENT         # prolog & root ELEMENT
    - DTD              # <!DOCTYPE ...>
    - DECLARATION      # <?xml attributes... ?>
    - COMMENT          # <!-- ... -->
    - CDATA            # <![CDATA[...]]>
    - ELEMENT          # <NAME attributes... > children... </NAME>
    - TEXT             # text
"""
@enum(NodeType, DOCUMENT, DTD, DECLARATION, COMMENT, CDATA, ELEMENT, TEXT)

#-----------------------------------------------------------------------------# RawDataType
"""
    RawDataType:
    RAW_TEXT                    # text
    RAW_COMMENT                 # <!-- ... -->
    RAW_CDATA                   # <![CDATA[...]]>
    RAW_DECLARATION             # <?xml attributes... ?>
    RAW_DTD                     # <!DOCTYPE ...>
    RAW_ELEMENT_OPEN            # <NAME attributes... >
    RAW_ELEMENT_CLOSE           # </NAME>
    RAW_ELEMENT_SELF_CLOSED     # <NAME attributes... />
    RAW_DOCUMENT                # Something to initilize with (not really used)
"""
@enum(RawDataType, RAW_DOCUMENT, RAW_TEXT, RAW_COMMENT, RAW_CDATA, RAW_DECLARATION, RAW_DTD,
    RAW_ELEMENT_OPEN, RAW_ELEMENT_CLOSE, RAW_ELEMENT_SELF_CLOSED)

nodetype(x::RawDataType) = x === RAW_ELEMENT_OPEN ? ELEMENT :
    x === RAW_ELEMENT_CLOSE ? ELEMENT :
    x === RAW_ELEMENT_SELF_CLOSED ? ELEMENT :
    x === RAW_TEXT ? TEXT :
    x === RAW_COMMENT ? COMMENT :
    x === RAW_CDATA ? CDATA :
    x === RAW_DECLARATION ? DECLARATION :
    x === RAW_DTD ? DTD :
    x === RAW_DOCUMENT ? DOCUMENT : nothing

#-----------------------------------------------------------------------------# RawData
"""
    RawData(filename::String)

Create an iterator over raw chunks of data in an XML file.  Each chunk of data represents one of:

    - RAW_DOCUMENT                # Only used to initialize the iterator state.
    - RAW_TEXT                    # text
    - RAW_COMMENT                 # <!-- ... -->
    - RAW_CDATA                   # <![CDATA[...]]>
    - RAW_DECLARATION             # <?xml attributes... ?>
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
    - children(o::RawData) --> Vector{RawData} of the children (or `nothing`).
    - parent(o::RawData) --> RawData of the parent (or `nothing`)
"""
struct RawData
    type::RawDataType
    depth::Int
    pos::Int
    len::Int
    data::Vector{UInt8}
end
function RawData(filename::String)
    data = Mmap.mmap(filename)
    RawData(RAW_DOCUMENT, 0, 0, 0, data)
end
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
Base.isdone(o::RawData) = o.pos + o.len ≥ length(o.data)

function Base.iterate(o::RawData, state=o)
    n = next(state)
    return isnothing(n) ? nothing : (n, n)
end


#-----------------------------------------------------------------------------# get_name
# find the start/stop of a name given a starting position `i`
_name_start(data, i) = findnext(x -> isletter(Char(x)) || Char(x) === '_', data, i)
is_name_char(x) = (c = Char(x); isletter(c) || isdigit(c) || c ∈ "._-:")
function _name_stop(data, i)
    i = findnext(!is_name_char, data, i)
    isnothing(i) ? nothing : i
end

# start at position i, return name and position after name
function get_name(data, i)
    i = _name_start(data, i)
    j = _name_stop(data, i)
    name = String(data[i:j-1])
    return name, j
end

#-----------------------------------------------------------------------------# get_attributes
function get_attributes(data)
    out = OrderedDict{String, String}()
    i = 1
    while !isnothing(i)
        # get key
        key, i = get_name(data, i)
        # get quotechar the value is wrapped in (either ' or ")
        i = findnext(x -> Char(x) === '"' || Char(x) === ''', data, i)
        quotechar = data[i]
        j = findnext(==(quotechar), data, i + 1)
        # get value and set it
        value = String(data[i+1:j-1])
        out[key] = value
        i = _name_start(data, j + 1)
    end
    return out
end

#-----------------------------------------------------------------------------# accessors
nodetype(o::RawData) = nodetype(o.type)

function tag(o::RawData)
    o.type ∉ [RAW_ELEMENT_OPEN, RAW_ELEMENT_CLOSE, RAW_ELEMENT_SELF_CLOSED] && return nothing
    return get_name(o.data, o.pos + 1)[1]
end

function attributes(o::RawData)
    if o.type === RAW_ELEMENT_OPEN || o.type === RAW_ELEMENT_SELF_CLOSED
        _, i = get_name(o.data, o.pos + 1)
        get_attributes(o.data, i)
    elseif o.type === RAW_DECLARATION
        get_attributes(@view(o.data[o.pos + 6:o.pos + o.len - 1]))
    else
        nothing
    end
end

function value(o::RawData)
    if o.type === RAW_TEXT
        String(o)
    elseif o.type === RAW_CDATA
        String(view(o.data, o.pos + 9 : o.pos + o.len - 3))
    elseif o.type === RAW_COMMENT
        String(view(o.data, o.pos + 4 : o.pos + o.len - 3))
    else
        nothing
    end
end

function children(o::RawData)
    if o.type === RAW_ELEMENT_OPEN
        depth = o.depth
        out = RawData[]
        for item in o
            # item.type === RAW_ELEMENT_CLOSE && continue
            item.depth == depth + 1 && push!(out, item)
            item.depth == depth && break
        end
        out
    else
        nothing
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



#-----------------------------------------------------------------------------# next RawData
notspace(x::UInt8) = !isspace(Char(x))

function next(o::RawData)
    i = o.pos + o.len + 1
    (; depth, data, type) = o
    i = findnext(notspace, data, i)  # skip insignificant whitespace
    isnothing(i) && return nothing
    if type === RAW_ELEMENT_OPEN || type === RAW_DOCUMENT
        depth += 1
    end
    c = Char(o.data[i])
    j = i + 1
    if c !== '<'
        type = RAW_TEXT
        j = findnext(==(UInt8('<')), data, i) - 1
    elseif c === '<'
        c2 = Char(o.data[i + 1])
        if c2 === '!'
            c3 = Char(o.data[i + 2])
            if c3 === '-'
                i += 1
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
            type = RAW_DECLARATION
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
    j = o.pos - 1
    j = findprev(notspace, data, j)  # skip insignificant whitespace
    isnothing(j) && return nothing
    c = Char(o.data[j])
    i = j - 1
    next_type = type
    if c !== '>' # text
        type = RAW_TEXT
        i = findprev(==(UInt8('>')), data, j) + 1
    elseif c === '>'
        c2 = Char(o.data[j - 1])
        if c2 === '-'
            type = RAW_COMMENT
            i = findprev(Vector{UInt8}("<--"), data, j)[1]
        elseif c2 === ']'
            type = RAW_CDATA
            i = findprev(Vector{UInt8}("<![CDATA["), data, j)[1]
        elseif c2 === '?'
            type = RAW_DECLARATION
            i = findprev(Vector{UInt8}("<?xml"), data, j)[1]
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


#-----------------------------------------------------------------------------# Lazy
# struct LazyNode
#     data::RawData
# end
# LazyNode(filename::AbstractString) = LazyNode(RawData(filename))



# Base.get(o::LazyNode) = RowNode(o.data)

# function next(o::LazyNode)
#     x = next(o.data)
#     isnothing(x) ? nothing : LazyNode(x)
# end
# function prev(o::LazyNode)
#     x = prev(o.data)
#     isnothing(x) ? nothing : LazyNode(x)
# end

# function Base.show(io::IO, o::LazyNode)
#     print(io, "LazyNode: ")
#     show(io, get(o))
# end
# function AbstractTrees.children(o::LazyNode)
#     depth = o.data.depth
#     out = LazyNode[]
#     x = o
#     while !isnothing(x)
#         x = next(x)
#         isnothing(x) && break
#         x.data.tok === TOK_END_ELEMENT && continue
#         x.data.depth == depth && break
#         x.data.depth == depth + 1 && push!(out, x)
#     end
#     return out
# end
# # AbstractTrees.nodevalue(o::LazyNode) = get(o)

# # function AbstractTrees.parent(o::LazyNode)
#     # TODO
# # end



#-----------------------------------------------------------------------------# RowNode
# struct RowNode
#     nodetype::NodeType
#     tag::Union{String, Nothing}
#     attributes::Union{OrderedDict{String, String}, Nothing}
#     value::Union{String, Nothing}
#     depth::Int
# end
# function RowNode(t::RawData)
#     (; type, pos, len, depth) = t
#     pos === 0 && return RowNode(DOCUMENT_NODE, nothing, nothing, nothing, 0)
#     data = view(t.data, pos:pos+len)
#     @views if type === RAW_TEXT  # text
#         return RowNode(TEXT_NODE, nothing, nothing, unescape(String(data), depth))
#     elseif type === RAW_COMMENT  # <!-- ... -->
#         return RowNode(COMMENT_NODE, nothing, nothing, String(data[4:end-3]), depth)
#     elseif type === RAW_CDATA  # <![CDATA[...]]>
#         return RowNode(CDATA_NODE, nothing, nothing, String(data[10:end-3]), depth)
#     elseif type === RAW_DECLARATION  # <?xml attributes... ?>
#         rng = 7:length(data) - 2
#         attributes = get_attributes(data[rng])
#         return RowNode(DECLARATION_NODE, nothing, attributes, nothing, depth)
#     elseif  type === RAW_DTD  # <!DOCTYPE ...>
#         return RowNode(DTD_NODE, nothing, nothing, String(data[10:end-1]), depth)
#     elseif type === RAW_ELEMENT_OPEN  # <NAME attributes... >
#         tag, i = get_name(data, 2)
#         i = findnext(x -> isletter(Char(x)) || x === UInt8('_'), data, i)
#         attributes = isnothing(i) ? nothing : get_attributes(data[i:end-1])
#         return RowNode(ELEMENT_NODE, tag, attributes, nothing, depth)
#     elseif type === RAW_ELEMENT_CLOSE  # </NAME>
#         return nothing
#     elseif  type === RAW_ELEMENT_SELF_CLOSED  # <NAME attributes... />
#         tag, i = get_name(data, 2)
#         i = findnext(x -> isletter(Char(x)) || x === UInt8('_'), data, i)
#         attributes = isnothing(i) ? nothing : get_attributes(data[i:end-2])
#         return RowNode(ELEMENT_NODE, tag, attributes, nothing, depth)
#     else
#         error("Unhandled token: $tok.")
#     end
# end

# AbstractTrees.children(o::RowNode) = missing

# Base.show(io::IO, o::RowNode) = _show_node(io, o)

# Base.IteratorSize(::Type{Rows}) = Base.SizeUnknown()
# Base.eltype(::Type{Rows}) = RowNode
# Base.isdone(o::Rows, pos) = isdone(o.file, pos)

# function Base.iterate(o::Rows, state = init(o.tokens))
#     n = next(state)
#     isnothing(n) && return nothing
#     n.tok === TOK_END_ELEMENT && return iterate(o, n)
#     return RowNode(n), n
# end


# #-----------------------------------------------------------------------------# Rows
# struct Rows
#     tokens::Tokens
# end
# Rows(filename::String) = Rows(Tokens(filename))
# Tables.rows(o::Rows) = o
# Tables.schema(o::Rows) = Tables.Schema(fieldnames(RowNode), fieldtypes(RowNode))

# struct RowNode
#     depth::Int
#     nodetype::NodeType
#     tag::Union{String, Nothing}
#     attributes::Union{OrderedDict{String, String}, Nothing}
#     value::Union{String, Nothing}
# end
# function RowNode(t::TokenData)
#     (; tok, pos, len, depth) = t
#     pos === 0 && return RowNode(0, DOCUMENT_NODE, nothing, nothing, nothing)
#     data = view(t.data, pos:pos+len)
#     @views if tok === TOK_TEXT  # text
#         return RowNode(depth, TEXT_NODE, nothing, nothing, unescape(String(data)))
#     elseif tok === TOK_COMMENT  # <!-- ... -->
#         return RowNode(depth, COMMENT_NODE, nothing, nothing, String(data[4:end-3]))
#     elseif tok === TOK_CDATA  # <![CDATA[...]]>
#         return RowNode(depth, CDATA_NODE, nothing, nothing, String(data[10:end-3]))
#     elseif tok === TOK_DECLARATION  # <?xml attributes... ?>
#         rng = 7:length(data) - 2
#         attributes = get_attributes(data[rng])
#         return RowNode(depth, DECLARATION_NODE, nothing, attributes, nothing)
#     elseif  tok === TOK_DTD  # <!DOCTYPE ...>
#         return RowNode(depth, DTD_NODE, nothing, nothing, String(data[10:end-1]))
#     elseif tok === TOK_START_ELEMENT  # <NAME attributes... >
#         tag, i = get_name(data, 2)
#         i = findnext(x -> isletter(Char(x)) || x === UInt8('_'), data, i)
#         attributes = isnothing(i) ? nothing : get_attributes(data[i:end-1])
#         return RowNode(depth, ELEMENT_NODE, tag, attributes, nothing)
#     elseif tok === TOK_END_ELEMENT  # </NAME>
#         return nothing
#     elseif  tok === TOK_SELF_CLOSED_ELEMENT  # <NAME attributes... />
#         tag, i = get_name(data, 2)
#         i = findnext(x -> isletter(Char(x)) || x === UInt8('_'), data, i)
#         attributes = isnothing(i) ? nothing : get_attributes(data[i:end-2])
#         return RowNode(depth, ELEMENT_NODE, tag, attributes, nothing)
#     else
#         error("Unhandled token: $tok.")
#     end
# end

# AbstractTrees.children(o::RowNode) = missing

# Base.show(io::IO, o::RowNode) = _show_node(io, o)

# Base.IteratorSize(::Type{Rows}) = Base.SizeUnknown()
# Base.eltype(::Type{Rows}) = RowNode
# Base.isdone(o::Rows, pos) = isdone(o.file, pos)

# function Base.iterate(o::Rows, state = init(o.tokens))
#     n = next(state)
#     isnothing(n) && return nothing
#     n.tok === TOK_END_ELEMENT && return iterate(o, n)
#     return RowNode(n), n
# end


# #-----------------------------------------------------------------------------# Node
# Base.@kwdef struct Node
#     nodetype::NodeType
#     tag::Union{Nothing, String} = nothing
#     attributes::Union{Nothing, OrderedDict{String, String}} = nothing
#     value::Union{Nothing, String} = nothing
#     children::Union{Nothing, Vector{Node}} = nothing
#     depth::Int = 0
# end
# function Node((;nodetype, tag, attributes, value, children, depth)::Node; kw...)
#     Node(; nodetype, tag, attributes, value, children, depth, kw...)
# end
# function (o::Node)(children...)
#     isempty(children) && return o
#     out = sizehint!(Node[], length(children))
#     foreach(children) do x
#         if x isa Node
#             push!(out, Node(x; depth=o.depth + 1))
#         else
#             push!(out, Node(nodetype=TEXT_NODE, value=string(x), depth=o.depth + 1))
#         end
#     end

#     Node(o; children=out)
# end

# function Node((; depth, nodetype, tag, attributes, value)::RowNode)
#     Node(; depth, nodetype, tag, attributes, value)
# end
# Node(o::TokenData) = Node(RowNode(o))

# function Base.:(==)(a::Node, b::Node)
#     a.nodetype == b.nodetype &&
#     a.tag == b.tag &&
#     a.attributes == b.attributes &&
#     a.value == b.value && (
#         (isnothing(a.children) && isnothing(b.children)) ||
#         (isnothing(a.children) && isempty(b.children)) ||
#         (isempty(a.children) && isnothing(b.children)) ||
#         all(ai == bi for (ai,bi) in zip(a.children, b.children))
#     )
# end

# # function element(nodetype::NodeType, tag = nothing; attributes...)
# #     attributes = isempty(attributes) ?
# #         nothing :
# #         OrderedDict(string(k) => string(v) for (k,v) in attributes)
# #     Node(; nodetype, tag, attributes)
# # end

# Base.getindex(o::Node, i::Integer) = o.children[i]
# Base.setindex!(o::Node, val, i::Integer) = o.children[i] = Node(val)
# Base.lastindex(o::Node) = lastindex(o.children)

# Base.push!(a::Node, b::Node) = push!(a.children, b)

# AbstractTrees.children(o::Node) = isnothing(o.children) ? [] : o.children

# Base.show(io::IO, o::Node) = _show_node(io, o)

# #-----------------------------------------------------------------------------# read
# read(filename::AbstractString) = Node(Tokens(filename))
# read(io::IO) = Node(Tokens("__UKNOWN_FILE__", read(io)))

# Node(filename::String) = Node(Tokens(filename))

# function Node(t::Tokens)
#     doc = Node(; nodetype=DOCUMENT_NODE, children=[])
#     stack = [doc]
#     for row in Rows(t)
#         temp = Node(row)
#         node = Node(temp; children = row.nodetype === ELEMENT_NODE ? [] : nothing)
#         filter!(x -> x.depth < node.depth, stack)
#         push!(stack[end], node)
#         push!(stack, node)
#     end
#     return doc
# end

# #-----------------------------------------------------------------------------# printing
function _show_node(io::IO, o)
    printstyled(io, 2o.depth, ':', o.nodetype, ' '; color=:light_green)
    if o.nodetype === TEXT_NODE
        printstyled(io, repr(o.value), color=:light_black)
    elseif o.nodetype === ELEMENT_NODE
        printstyled(io, '<', o.tag, color=:light_cyan)
        _print_attrs(io, o)
        printstyled(io, '>', color=:light_cyan)
        _print_n_children(io, o)
    elseif o.nodetype === DTD_NODE
        printstyled(io, "<!DOCTYPE", o.tag, color=:light_cyan)
        printstyled(io, o.value, color=:light_black)
        printstyled(io, '>', color=:light_cyan)
    elseif o.nodetype === DECLARATION_NODE
        printstyled(io, "<?xml", color=:light_cyan)
        _print_attrs(io, o)
        printstyled(io, '>', color=:light_cyan)
    elseif o.nodetype === COMMENT_NODE
        printstyled(io, "<!--", color=:light_cyan)
        printstyled(io, o.value, color=:light_black)
        printstyled(io, "-->", color=:light_cyan)
    elseif o.nodetype === CDATA_NODE
        printstyled(io, "<![CDATA[", color=:light_cyan)
        printstyled(io, o.value, color=:light_black)
        printstyled(io, "]]>", color=:light_cyan)
    elseif o.nodetype === DOCUMENT_NODE
        printstyled(io, "Document", color=:light_cyan)
        _print_n_children(io, o)
    elseif o.nodetype === UNKNOWN_NODE
        printstyled(io, "Unknown", color=:light_cyan)
        _print_n_children(io, o)
    else
        error("Unreachable reached")
    end
end

function _print_attrs(io::IO, o)
    !isnothing(o.attributes) && printstyled(io, [" $k=\"$v\"" for (k,v) in o.attributes]...; color=:light_black)
end
function _print_n_children(io::IO, o)
    children = AbstractTrees.children(o)
    printstyled(io, ismissing(children) || isnothing(children) ? "" : " ($(length(children)) children)", color=:light_black)
end

# #-----------------------------------------------------------------------------# write_xml
# write(x::Node) = (io = IOBuffer(); write(io, x); String(take!(io)))

# write(filename::AbstractString, x::Node) = open(io -> write(io, x), filename, "w")

# function write(io::IO, x::Node; indent = "   ")
#     padding = indent ^ max(0, x.depth - 1)
#     print(io, padding)
#     if x.nodetype === TEXT_NODE
#         print(io, escape(x.value))
#     elseif x.nodetype === ELEMENT_NODE
#         print(io, '<', x.tag)
#         _print_attrs(io, x)
#         print(io, isnothing(x.children) ? '/' : "", '>')
#         single_text_child = !isnothing(x.children) && length(x.children) == 1 && x.children[1].nodetype === TEXT_NODE
#         if single_text_child
#             write(io, only(x.children); indent="")
#             print(io, "</", x.tag, '>')
#         elseif !isnothing(x.children)
#             println(io)
#             foreach(AbstractTrees.children(x)) do child
#                 write(io, child; indent)
#                 println(io)
#             end
#             print(io, padding, "</", x.tag, '>')
#         end
#     elseif x.nodetype === DTD_NODE
#         print(io, "<!DOCTYPE", x.value, '>')
#     elseif x.nodetype === DECLARATION_NODE
#         print(io, "<?xml")
#         _print_attrs(io, x)
#         print(io, "?>")
#     elseif x.nodetype === COMMENT_NODE
#         print(io, "<!--", x.value, "-->")
#     elseif x.nodetype === CDATA_NODE
#         print(io, "<![CDATA[", x.value, "]]>")
#     elseif x.nodetype === DOCUMENT_NODE
#         foreach(AbstractTrees.children(x)) do child
#             write(io, child; indent)
#             println(io)
#         end
#     else
#         error("Unreachable case reached during XML.write")
#     end
# end

end
