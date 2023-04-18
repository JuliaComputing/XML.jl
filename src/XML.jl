module XML

using OrderedCollections: OrderedDict
using Base: @kwdef, StringVector
using Mmap
using Tables
# import AbstractTrees: print_tree, printnode, children

export Document, DTD, Declaration, Comment, CData, Element,
    children, tag, attributes

#-----------------------------------------------------------------------------# escape/unescape
escape_chars = ['&' => "&amp;", '"' => "&quot;", ''' => "&#39;", '<' => "&lt;", '>' => "&gt;"]
escape(x::AbstractString) = replace(x, escape_chars...)
unescape(x::AbstractString) = replace(x, reverse.(escape_chars)...)

#-----------------------------------------------------------------------------# NodeType
@enum(NodeType,
    DOCUMENT_NODE,          # prolog & root ELEMENT_NODE
    DTD_NODE,               # <!DOCTYPE ...>
    DECLARATION_NODE,       # <?xml attributes... ?>
    COMMENT_NODE,           # <!-- ... -->
    CDATA_NODE,             # <![CDATA[...]]>
    ELEMENT_NODE,           # <NAME attributes... > children... </NAME>
    TEXT_NODE,              # text
    UNKNOWN_NODE,           # unknown
)

#-----------------------------------------------------------------------------# XMLToken
@enum(XMLToken,
    TOK_TEXT,                   # text
    TOK_COMMENT,                # <!-- ... -->
    TOK_CDATA,                  # <![CDATA[...]]>
    TOK_DECLARATION,            # <?xml attributes... ?>
    TOK_DTD,                    # <!DOCTYPE ...>
    TOK_START_ELEMENT,          # <NAME attributes... >
    TOK_END_ELEMENT,            # </NAME>
    TOK_SELF_CLOSED_ELEMENT,    # <NAME attributes... />
    TOK_UNKNOWN                 # Something to initilize with
)

#-----------------------------------------------------------------------------# Tokens
struct Tokens
    filename::String
    data::Vector{UInt8}
    Tokens(filename::String) = new(filename, Mmap.mmap(filename))
end
Tables.rows(o::Tokens) = o
Tables.schema(o::Tokens) = Tables.Schema(fieldnames(TokenData), fieldtypes(TokenData))

struct TokenData
    tok::XMLToken
    depth::Int
    pos::Int
    data::typeof(view(Vector{UInt8}("example"), 1:2))
end
function Base.show(io::IO, o::TokenData)
    print(io, o.tok)
    printstyled(io, " (depth=", o.depth, ", ", "pos=", o.pos, ") : "; color=:light_black)
    printstyled(io, String(copy(o.data)); color=:light_green)
end

Base.IteratorSize(::Type{Tokens}) = Base.SizeUnknown()
Base.eltype(::Type{Tokens}) = TokenData
Base.isdone(o::Tokens, pos) = pos ≥ length(o.data)

# state = (position_in_data, depth)
function Base.iterate(o::Tokens, state = (1, 1))
    i, depth = state
    Base.isdone(o, i) && return nothing
    data = o.data
    i = findnext(x -> !isspace(Char(x)), data, i)  # skip insignificant whitespace
    c = Char(o.data[i])
    tok = TOK_UNKNOWN
    if isletter(c)
        tok = TOK_TEXT
        j = findnext(==(UInt8('<')), data, i) - 1
    elseif c === '<'
        c2 = Char(o.data[i + 1])
        if c2 === '!'
            c3 = Char(o.data[i + 2])
            if c3 === '-'
                tok = TOK_COMMENT
                j = findnext(Vector{UInt8}("-->"), data, i)[end]
            elseif c3 === '['
                tok = TOK_CDATA
                j = findnext(Vector{UInt8}("]]>"), data, i)[end]
            elseif c3 === 'D'
                tok = TOK_DTD
                j = findnext(x -> x == UInt8('>'), data, i)
            else
                error("Should be unreachable.  Unexpected token: $c$c2$c3")
            end
        elseif c2 === '?'
            tok = TOK_DECLARATION
            j = findnext(Vector{UInt8}("?>"), data, i)[end]
        elseif c2 === '/'
            tok = TOK_END_ELEMENT
            j = findnext(==(UInt8('>')), data, i)
            depth -= 1
        else
            j = findnext(==(UInt8('>')), data, i)
            if data[j-1] === UInt8('/')
                tok = TOK_SELF_CLOSED_ELEMENT
            else
                depth += 1
                tok = TOK_START_ELEMENT
            end
        end
    else
        error("Unexpected character: $c")
    end
    tok === TOK_UNKNOWN && error("Token isn't identified: $(String(data[i:j]))")
    return TokenData(tok, depth, i, view(o.data, i:j)) => (j + 1, depth)
end


#-----------------------------------------------------------------------------# Rows
struct Rows
    tokens::Tokens
end
Rows(filename::String) = Rows(Tokens(filename))
Tables.rows(o::Rows) = o
Tables.schema(o::Rows) = Tables.Schema(fieldnames(RowNode), fieldtypes(RowNode))

struct RowNode
    depth::Int
    nodetype::NodeType
    tag::Union{String, Nothing}
    attributes::Union{OrderedDict{String, String}, Nothing}
    value::Union{String, Nothing}
end
function Base.show(io::IO, o::RowNode)
    printstyled(io, lpad("$(o.depth)", 2o.depth), ':', o.nodetype, ' '; color=:light_green)
    if o.nodetype === TEXT_NODE
        printstyled(io, repr(o.value), color=:light_black)
    elseif o.nodetype === ELEMENT_NODE
        printstyled(io, '<', o.tag, color=:light_cyan)
        _print_attrs(io, o)
        printstyled(io, '>', color=:light_cyan)
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
    elseif o.nodetype === UNKNOWN_NODE
        printstyled(io, "Unknown", color=:light_cyan)
    else
        error("Unreachable reached")
    end
end
function _print_attrs(io::IO, o)
    !isnothing(o.attributes) && printstyled(io, [" $k=\"$v\"" for (k,v) in o.attributes]...; color=:light_black)
end

Base.IteratorSize(::Type{Rows}) = Base.SizeUnknown()
Base.eltype(::Type{Rows}) = RowNode
Base.isdone(o::Rows, pos) = isdone(o.file, pos)


# Same `state` as Tokens
function Base.iterate(o::Rows, state = (1,1))
    next = iterate(o.tokens, state)
    isnothing(next) && return nothing
    tokendata, state = next
    (i, depth) = state
    (; tok, data) = tokendata

    out = @views if tok === TOK_TEXT  # text
        RowNode(depth, TEXT_NODE, nothing, nothing, unescape(String(data)))
    elseif tok === TOK_COMMENT  # <!-- ... -->
        RowNode(depth, COMMENT_NODE, nothing, nothing, String(data[4:end-3]))
    elseif tok === TOK_CDATA  # <![CDATA[...]]>
        RowNode(depth, CDATA_NODE, nothing, nothing, String(data[10:end-3]))
    elseif tok === TOK_DECLARATION  # <?xml attributes... ?>
        rng = 7:length(data) - 2
        attributes = get_attributes(data[rng])
        RowNode(depth, DECLARATION_NODE, nothing, attributes, nothing)
    elseif  tok === TOK_DTD  # <!DOCTYPE ...>
        RowNode(depth, DTD_NODE, nothing, nothing, String(data[10:end-1]))
    elseif tok === TOK_START_ELEMENT  # <NAME attributes... >
        tag, i = get_name(data, 2)
        i = findnext(x -> isletter(Char(x)) || x === UInt8('_'), data, i)
        attributes = isnothing(i) ? nothing : get_attributes(data[i:end-1])
        RowNode(depth, ELEMENT_NODE, tag, attributes, nothing)
    elseif tok === TOK_END_ELEMENT  # </NAME>
        return iterate(o, state)
    elseif  tok === TOK_SELF_CLOSED_ELEMENT  # <NAME attributes... />
        tag, i = get_name(data, 2)
        i = findnext(x -> isletter(Char(x)) || x === UInt8('_'), data, i)
        attributes = isnothing(i) ? nothing : get_attributes(data[i:end-2])
        RowNode(depth, ELEMENT_NODE, tag, attributes, nothing)
    else
        error("Unhandled token: $tok.")
    end

    return out => state
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

















#-----------------------------------------------------------------------------# Node
@kwdef struct Node
    nodetype::NodeType
    tag::Union{Nothing, String} = nothing
    attributes::Union{Nothing, OrderedDict{String, String}} = nothing
    content::Union{Nothing, String} = nothing
    children::Union{Nothing, Vector{Node}} = nothing
    depth::Union{Nothing, Int} = nothing
end
Node(nodetype::NodeType; kw...) = Node(; nodetype, kw...)
function Node(o::Node; kw...)
    Node(; nodetype=o.nodetype, tag=o.tag, attributes=o.attributes, content=o.content, children=o.children, depth=o.depth, kw...)
end

#-----------------------------------------------------------------------------# printing
function _show_node(io, o)
    printstyled(io, lpad("$(o.depth)", 2o.depth), ':', o.nodetype, ' '; color=:light_green)
    if o.nodetype === TEXT_NODE
        printstyled(io, repr(o.content), color=:light_black)
    elseif o.nodetype === ELEMENT_NODE
        printstyled(io, '<', o.tag, color=:light_cyan)
        _print_attrs(io, o)
        printstyled(io, '>', color=:light_cyan)
        _print_n_children(io, o)
    elseif o.nodetype === DTD_NODE
        printstyled(io, "<!DOCTYPE", o.tag, color=:light_cyan)
        printstyled(io, o.content, color=:light_black)
        printstyled(io, '>', color=:light_cyan)
    elseif o.nodetype === DECLARATION_NODE
        printstyled(io, "<?xml", color=:light_cyan)
        _print_attrs(io, o)
        printstyled(io, '>', color=:light_cyan)
    elseif o.nodetype === COMMENT_NODE
        printstyled(io, "<!--", color=:light_cyan)
        printstyled(io, o.content, color=:light_black)
        printstyled(io, "-->", color=:light_cyan)
    elseif o.nodetype === CDATA_NODE
        printstyled(io, "<![CDATA[", color=:light_cyan)
        printstyled(io, o.content, color=:light_black)
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

Base.getindex(o::Node, i::Integer) = o.children[i]
Base.setindex!(o::Node, val, i::Integer) = o.children[i] = Node(val)
Base.lastindex(o::Node) = lastindex(o.children)

Base.push!(a::Node, b::Node) = push!(a.children, b)

Base.read(filename::AbstractString, ::Type{Node}) = open(io -> read(io, Node), filename)

function Base.read(io::IO, ::Type{Node})
    doc = Node(DOCUMENT_NODE, depth=0, children=[])
    all_nodes = [doc]
    for node in StreamingIterator(io)
        item = node.nodetype === ELEMENT_NODE ? _with_children(node) : node
        filter!(x -> x.depth < node.depth, all_nodes)
        push!(all_nodes, item)
        push!(all_nodes[end-1], item)
    end
    return doc
end

_with_children(o::Node) = isnothing(o.children) ? Node(o, children=Node[]) : o
























# #-----------------------------------------------------------------------------# File
# struct File
#     io::IO
#     vec::Vector{UInt8}
# end
# File(io::IO) = File(io, StringVector(0))
# File(file::AbstractString) = open(io -> File(io), file, "r")


# # Everything but the children in a Node
# struct Part
#     nodetype::NodeType
#     tag::Union{Nothing, Symbol}
#     attributes::Union{Nothing, OrderedDict{Symbol, String}}
#     content::Union{Nothing, String}
#     location::Vector{Int}
# end
# function Base.show(io::IO, o::Part)
#     f = Fields(o)
#     print(io, "Part(", f.nodetype, "): ")
#     !isnothing(f.tag) && printstyled(io, '<', f.tag, color=:light_cyan)
#     !isnothing(f.attributes) && print(io, ' ', join(["$k=\"$v\"" for (k,v) in f.attributes], ' '))
#     !isnothing(f.tag) && printstyled(io, '>', color=:light_cyan)
#     !isnothing(f.content) && printstyled(io, repr(f.content), color=:light_black)
# end

# Base.IteratorSize(::Type{<:File}) = Base.SizeUnknown()
# Base.eltype(::Type{File}) = Part


# function Base.iterate(o::File, state=(idx=0, parent_tags=Symbol[]))
#     (;io, vec) = o
#     state.idx === 0 && seekstart(io)
#     eof(io) && return nothing
#     next_state = (idx = state.idx + 1, parent_tags = state.parent_tags)
#     skipchars(isspace, io)
#     char = read(io, Char)

#     # Case 1: return TEXT_NODE
#     if char !== '<'
#         content = read_until(!=('<'), o)
#         return Part(TEXT_NODE, nothing, nothing, string(char) * content) => next_state
#     end

#     # Case 2: ELEMENT_NODE
#     if isletter(peek(io, Char))
#         tag = read_tag(io, o)
#         attrs = read_attributes(io, o)
#         @info "tag: $tag, attrs: $attrs"
#         s = readuntil(io, '>')
#         '/' in s && push!(next_state.parent_tags, tag)
#         return Part(ELEMENT_NODE, tag, attrs, nothing), next_state
#     end

#     char2 = read(io, Char)

#     # Case 3: closing tag.  Adjust parent_tags and keep reading until we find the next thing.
#     if char2 === '/'
#         tag = read_tag(io, o)
#         if tag === last(parent_tags)
#             closed_tag = pop!(next_state.parent_tags)
#             read(io, Char) === '>' || error("Expected '>' after closing tag </$closed_tag.")
#             skipchars(isspace, io)
#         else
#             error("Found unexpected closing tag $tag.  Expected: $(last(parent_tags)).")
#         end
#     end

#     # Case 4: DECLARATION_NODE <?xml attributes... ?>
#     if char2 === '?'
#         tag = read_tag(io, o)
#         tag === :xml || error("Expected '<?xml'.  Found '<?$tag'.")
#         attrs = read_attributes(io, o)
#         readuntil(io, "?>")
#         return Part(DECLARATION_NODE, nothing, attrs, nothing), next_state
#     end

#     # Case 5: Comment / CDATA / DTD
#     if char2 === '!'
#         char3 = read(io, Char)
#         if char3 === '-' # Comment
#             read(io, Char) === '-' || error("Expected '<!--'.  Found '<!-$char3'.")
#             content = readuntil(io, "-->", keep=false)
#             skip(io, 3)
#             return Part(COMMENT_NODE, nothing, nothing, content), next_state
#         elseif char3 === '[' # CDATA
#             read(io, 6) === "CDATA[" || error("Expected '<![CDATA['.  Found '<![$char3'.")
#             content = readuntil(io, "]]>", keep=false)
#             skip(io, 3)
#             return Part(CDATA_NODE, nothing, nothing, content), next_state
#         elseif char3 === 'D' || char3 === 'd' # DTD
#             # TODO: all the messy details of DTD
#             skip(io, 6)
#             content = readuntil(io, '>', keep=false)
#             return Part(DTD_NODE, nothing, nothing, content), next_state
#         else
#             error("Unknown node beginning with: '<!$char3'.")
#         end
#     end
#     error("Unknown node beginning with: '<$char2'.")
# end

# function read_until(predicate, io::IO, o::File)
#     while !predicate(peek(io, Char))
#         push!(o.vec, read(io, Char))
#     end
#     String(o.vec)
# end

# read_tag(io::IO, o::File) = Symbol(read_until(!isletter, io, o))

# function read_attributes(io::IO, o::File)
#     skipchars(isspace, io)
#     peek(io, Char) in "/>" && return nothing
#     attrs = OrderedDict{Symbol, String}()
#     while true
#         skipchars(isspace, io)
#         char = peek(io, Char)
#         (isspace(char) || char in "?/>") && break
#         key = read_tag(io, o)
#         @info "Key=$key"
#         skipchars(isspace, io)
#         read(io, Char) === '=' || error("Expected '=' after attribute name.")
#         skipchars(isspace, io)
#         char2 = read(io, Char)
#         val = readuntil(io, char2; keep=false)
#         @info "Val=$val"
#         attrs[Symbol(key)] = val
#     end
#     return attrs
# end





# # #-----------------------------------------------------------------------------# LazyNode
# # struct LazyNode
# #     nodetype::NodeType
# #     tag::Union{Nothing, Symbol}
# #     attributes::Union{Nothing, Dict{Symbol, String}}
# #     content
# # end


# # #-----------------------------------------------------------------------------# SimpleNode
# # struct SimpleNode
# #     nodetype::NodeType
# #     tag::Union{Nothing, String}
# #     attributes::Union{Nothing, Dict{String, String}}
# #     content::Union{Nothing, String}
# #     index::Int
# #     parent::Int
# # end
# # #-----------------------------------------------------------------------------# SimpleDocument
# # struct SimpleDocument
# #     io::IO
# #     nodes::Vector{SimpleNode}
# # end
# # SimpleDocument(file::AbstractString) = SimpleDocument(open(io -> SimpleDocument(io), file, "r"))
# # function SimpleDocument(io::IO)
# #     nodes = SimpleNode[]
# #     while !eof(io)
# #         add_simplenode!(nodes, io)
# #     end
# # end

# # function add_simplenode!(nodes, io)
# #     (;parent, index) = isempty(nodes) ? (parent=0,index=0) : last(nodes)
# #     skipchars(isspace, io)
# #     start = position(io)
# #     char = peek(io, Char)

# #     nodetype = if char !== '<'
# #         TEXT_NODE
# #     elseif char === '?'
# #         DECLARATION_NODE
# #     elseif char === '!'
# #         # DTD or CDATA or COMMENT
# #     end



# #     #---------------------------- TEXT_NODE
# #     if char !== '<'
# #         content = readuntil(io, '<', keep=false)
# #         push!(nodes, SimpleNode(TEXT_NODE, nothing, nothing, content, parent, index + 1))
# #     else
# #         skip(io, 1) # '<'
# #         char = peek(io, Char)
# #         if char === '?'
# #             #---------------------------- DECLARATION_NODE
# #             readuntil(io, "?xml", keep=false)
# #             push!(nodes, SimpleNode(DECLARATION_NODE, nothing, get_attributes(io), nothing, parent, index + 1))
# #         elseif char === '!'
# #             char = read(io, Char)
# #             if char === 'D'
# #                 #---------------------------- DTD_NODE
# #                 readuntil(io, "DOCTYPE")
# #                 push!(nodes, SimpleNode(DTD_NODE, nothing, get_attributes(io), nothing, parent, index + 1))
# #             elseif char === '['
# #                 #---------------------------- CDATA_NODE
# #                 readuntil(io, "[CDATA[", keep=true)
# #                 content = readuntil(io, "]]>", keep=false)
# #                 push!(nodes, SimpleNode(CDATA_NODE, nothing, nothing, content, parent, index + 1))
# #             elseif char === '-'
# #                 #---------------------------- COMMENT_NODE
# #                 read(io, Char) == '-' && read(io, Char) == '-' || error("Expected `<!--`")
# #                 content = readuntil(io, "-->", keep=false)
# #                 push!(nodes, SimpleNode(COMMENT_NODE, nothing, nothing, content, parent, index + 1))
# #             else
# #                 error("Unknown node type: <!$(char)")
# #             end
# #         else
# #             #---------------------------- ELEMENT_NODE
# #             push!(nodes, SimpleNode(ELEMENT_NODE, get_tag(io), get_attributes(io), nothing, parent, index + 1))

# #         end
# #     end
# # end

# # function get_tag(io)
# #     buf = IOBuffer()
# #     while true
# #         char = read(io, Char)
# #         if isspace(char) || char === '>' || char === '/'
# #             break
# #         end
# #         write(buf, char)
# #     end
# #     tag = String(take!(buf))
# #     # @info tag
# #     return tag
# # end






# # function get_next(o::XMLIterator, i::Int)
# #     if
# #     if !isempty(o.siblings_below)
# #         push!(o.sib)
# #     else
# #     end
# #     io = o.io
# #     skipchars(isspace, io)
# #     char = read(io, Char)
# #     if char === '<'
# #     else
# #     end
# # end

# # #-----------------------------------------------------------------------------# XMLTokenIterator
# # @enum(TokenType,
# #     UNKNOWNTOKEN,           # ???
# #     DTDTOKEN,               # <!DOCTYPE ...>
# #     DECLARATIONTOKEN,       # <?xml attributes... ?>
# #     COMMENTTOKEN,           # <!-- ... -->
# #     CDATATOKEN,             # <![CDATA[...]]>
# #     ELEMENTTOKEN,           # <NAME attributes... >
# #     ELEMENTSELFCLOSEDTOKEN, # <NAME attributes... />
# #     ELEMENTCLOSETOKEN,      # </NAME>
# #     TEXTTOKEN               # text between a '>' and a '<'
# # )

# # mutable struct XMLTokenIterator{IOT <: IO}
# #     io::IOT
# #     start_pos::Int64  # position(io) always returns Int64?
# #     buffer::IOBuffer
# # end
# # XMLTokenIterator(io::IO) = XMLTokenIterator(io, position(io), IOBuffer())

# # readchar(o::XMLTokenIterator) = (c = read(o.io, Char); write(o.buffer, c); c)
# # reset(o::XMLTokenIterator) = o.start_pos == 0 ? seekstart(o.io) : seek(o.io, o.start_pos)

# # function readuntil(o::XMLTokenIterator, char::Char)
# #     c = readchar(o)
# #     while c != char
# #         c = readchar(o)
# #     end
# # end
# # function readuntil(o::XMLTokenIterator, pattern::String)
# #     chars = collect(pattern)
# #     last_chars = similar(chars)
# #     while last_chars != chars
# #         for i in 1:(length(chars) - 1)
# #             last_chars[i] = last_chars[i+1]
# #         end
# #         last_chars[end] = readchar(o)
# #     end
# # end

# # function Base.iterate(o::XMLTokenIterator, state=0)
# #     state == 0 && reset(o)
# #     pair = next_token(o)
# #     isnothing(pair) ? nothing : (pair, state + 1)
# # end

# # function next_token(o::XMLTokenIterator)
# #     io = o.io
# #     buffer = o.buffer
# #     skipchars(isspace, io)
# #     eof(io) && return nothing
# #     foreach(_ -> readchar(o), 1:3)
# #     s = String(take!(buffer))
# #     skip(io, -3)
# #     pair = if startswith(s, "<!D") || startswith(s, "<!d")
# #         readuntil(o, '>')
# #         DTDTOKEN => String(take!(buffer))
# #     elseif startswith(s, "<![")
# #         readuntil(o, "]]>")
# #         CDATATOKEN => String(take!(buffer))
# #     elseif startswith(s, "<!-")
# #         readuntil(o, "-->")
# #         COMMENTTOKEN => String(take!(buffer))
# #     elseif startswith(s, "<?x")
# #         readuntil(o, "?>")
# #         DECLARATIONTOKEN => String(take!(buffer))
# #     elseif startswith(s, "</")
# #         readuntil(o, '>')
# #         ELEMENTCLOSETOKEN => String(take!(buffer))
# #     elseif startswith(s, "<")
# #         readuntil(o, '>')
# #         s = String(take!(buffer))
# #         t = endswith(s, "/>") ? ELEMENTSELFCLOSEDTOKEN : ELEMENTTOKEN
# #         t => s
# #     else
# #         readuntil(o, '<')
# #         skip(io, -1)
# #         TEXTTOKEN => unescape(String(take!(buffer)[1:end-1]))
# #     end
# #     return pair
# # end


# # Base.eltype(::Type{<:XMLTokenIterator}) = Pair{TokenType, String}

# # Base.IteratorSize(::Type{<:XMLTokenIterator}) = Base.SizeUnknown()

# # Base.isdone(itr::XMLTokenIterator, state...) = eof(itr.io)

# # #-----------------------------------------------------------------------------# AbstractXMLNode
# # abstract type AbstractXMLNode end

# # Base.show(io::IO, ::MIME"text/plain", o::AbstractXMLNode) = showxml(io, o)
# # Base.show(io::IO, ::MIME"text/xml", o::AbstractXMLNode) = showxml(io, o)
# # Base.show(io::IO, ::MIME"application/xml", o::AbstractXMLNode) = showxml(io, o)

# # Base.write(io::IO, node::AbstractXMLNode) = foreach(x -> showxml(io, x), children(node))

# # function Base.:(==)(a::T, b::T) where {T <: AbstractXMLNode}
# #     all(getfield(a, f) == getfield(b, f) for f in fieldnames(T))
# # end

# # const INDENT = "  "

# # showxml(x; depth=0) = (io=IOBuffer(); showxml(io, x); print(String(take!(io))))

# # # assumes '\n' occurs in String
# # showxml(io::IO, x::String; depth=0) = print(io, INDENT^depth, x)

# # printnode(io::IO, o::AbstractXMLNode) = showxml(io, o)


# # #-----------------------------------------------------------------------------# DTD
# # # TODO: all the messy details of DTD.  For now, just dump everything into `text`
# # struct DTD <: AbstractXMLNode
# #     text::String
# # end
# # showxml(io::IO, o::DTD; depth=0) = print(io, INDENT^depth, "<!DOCTYPE ", o.text, '>')


# # #-----------------------------------------------------------------------------# Declaration
# # mutable struct Declaration <: AbstractXMLNode
# #     tag::String
# #     attributes::OrderedDict{Symbol, String}
# # end
# # function showxml(io::IO, o::Declaration; depth=0)
# #     print(io, INDENT ^ depth, "<?", o.tag)
# #     print_attributes(io, o)
# #     print(io, "?>")
# # end
# # attributes(o::Declaration) = o.attributes

# # #-----------------------------------------------------------------------------# CData
# # mutable struct CData <: AbstractXMLNode
# #     text::String
# # end
# # showxml(io::IO, o::CData; depth=0) = printstyled(io, INDENT ^ depth, "<![CDATA[", o.text, "]]>", color=:light_black)


# # #-----------------------------------------------------------------------------# Comment
# # mutable struct Comment <: AbstractXMLNode
# #     text::String
# # end
# # showxml(io::IO, o::Comment; depth=0) = printstyled(io, INDENT ^ depth, "<!-- ", escape(o.text), " -->", color=:light_black)

# # #-----------------------------------------------------------------------------# Element
# # mutable struct Element <: AbstractXMLNode
# #     tag::String
# #     attributes::OrderedDict{Symbol, String}
# #     children::Vector{Union{CData, Comment, Element, String}}
# #     function Element(tag="UNDEF", attributes=OrderedDict{Symbol,String}(), children=Union{CData, Comment, Element, String}[])
# #         new(tag, attributes, children)
# #     end
# # end
# # function h(tag::String, children...; attrs...)
# #     attributes = OrderedDict{Symbol,String}(k => string(v) for (k,v) in pairs(attrs))
# #     Element(tag, attributes, collect(children))
# # end

# # function showxml(io::IO, o::Element; depth=0)
# #     print(io, INDENT ^ depth, '<')
# #     printstyled(io, tag(o), color=:light_cyan)
# #     print_attributes(io, o)
# #     n = length(children(o))
# #     if n == 0
# #         print(io, "/>")
# #     elseif n == 1 && children(o)[1] isa String
# #         s = children(o)[1]
# #         print(io, '>', s, "</")
# #         printstyled(io, tag(o), color=:light_cyan)
# #         print(io, '>')
# #     else
# #         print(io, '>')
# #         for child in children(o)
# #             println(io)
# #             showxml(io, child; depth=depth + 1)
# #         end
# #         print(io, '\n', INDENT^depth, "</")
# #         printstyled(io, tag(o), color=:light_cyan)
# #         print(io, '>')
# #     end
# # end

# # Base.show(io::IO, o::Element) = print_tree(io, o)

# # function printnode(io::IO, o::Element, color=:light_cyan)
# #     print(io, '<')
# #     printstyled(io, tag(o), color=color)
# #     print_attributes(io, o)
# #     n = length(children(o))
# #     if n == 0
# #         print(io, "/>")
# #     else
# #         print(io, '>')
# #         printstyled(io, " (", length(children(o)), n > 1 ? " children)" : " child)", color=:light_black)
# #     end
# # end

# # function print_attributes(io::IO, o::AbstractXMLNode)
# #     foreach(pairs(attributes(o))) do (k,v)
# #         printstyled(io, ' ', k, '='; color=:green)
# #         printstyled(io, '"', v, '"'; color=:light_green)
# #     end
# # end

# # children(o::Element) = getfield(o, :children)
# # tag(o::Element) = getfield(o, :tag)
# # attributes(o::Element) = getfield(o, :attributes)

# # Base.getindex(o::Element, i::Integer) = children(o)[i]
# # Base.lastindex(o::Element) = lastindex(children(o))
# # Base.setindex!(o::Element, val::Element, i::Integer) = setindex!(children(o), val, i)
# # Base.push!(o::Element, val::Element) = push!(children(o), val)

# # Base.getproperty(o::Element, x::Symbol) = attributes(o)[x]
# # Base.setproperty!(o::Element, x::Symbol, val) = (attributes(o)[x] = string(val))
# # Base.propertynames(o::Element) = collect(keys(attributes(o)))

# # Base.get(o::Element, key::Symbol, val) = hasproperty(o, key) ? getproperty(o, key) : val
# # Base.get!(o::Element, key::Symbol, val) = hasproperty(o, key) ? getproperty(o, key) : setproperty!(o, key, val)




# # #-----------------------------------------------------------------------------# Document
# # mutable struct Document <: AbstractXMLNode
# #     prolog::Vector{Union{Comment, Declaration, DTD}}
# #     root::Element
# #     Document(prolog=Union{Comment,Declaration,DTD}[], root=Element()) = new(prolog, root)
# # end

# # function Document(o::XMLTokenIterator)
# #     doc = Document()
# #     populate!(doc, o)
# #     return doc
# # end

# # Document(file::String) = open(io -> Document(XMLTokenIterator(io)), file, "r")
# # Document(io::IO) = Document(XMLTokenIterator(io))

# # Base.show(io::IO, ::MIME"text/plain", o::Document) = print_tree(io, o; maxdepth=1)

# # printnode(io::IO, o::Document) = print(io, "XML.Document")

# # children(o::Document) = (o.prolog..., o.root)

# # showxml(io::IO, o::Document; depth=0) = foreach(x -> (showxml(io, x), println(io)), children(o))

# # #-----------------------------------------------------------------------------# makers (AbstractXMLNode from a token)
# # make_dtd(s) = DTD(replace(s, "<!doctype " => "", "<!DOCTYPE " => "", '>' => ""))
# # make_declaration(s) = Declaration(get_tag(s), get_attributes(s))
# # make_comment(s) = Comment(replace(s, "<!-- " => "", " -->" => ""))
# # make_cdata(s) = CData(replace(s, "<![CDATA[" => "", "]]>" => ""))
# # make_element(s) = Element(get_tag(s), get_attributes(s))

# # get_tag(x) = @inbounds x[findfirst(r"[a-zA-z][^\s>/]*", x)]  # Matches: (any letter) → (' ', '/', '>')
# # # get_tag(x) = match(r"[a-zA-z][^\s>/]*", x).match  # Matches: (any letter) → (' ', '/', '>')

# # function get_attributes(x)
# #     out = OrderedDict{Symbol,String}()
# #     rng = findfirst(r"(?<=\s).*\"", x)
# #     isnothing(rng) && return out
# #     s = x[rng]
# #     kys = (m.match for m in eachmatch(r"[a-zA-Z][a-zA-Z\.-_]*(?=\=)", s))
# #     vals = (m.match for m in eachmatch(r"(?<=(\=\"))[^\"]*", s))
# #     foreach(zip(kys,vals)) do (k,v)
# #         out[Symbol(k)] = v
# #     end
# #     out
# # end



# # #-----------------------------------------------------------------------------# populate!
# # function populate!(doc::Document, o::XMLTokenIterator)
# #     for (T, s) in o
# #         if T == DTDTOKEN
# #             push!(doc.prolog, make_dtd(s))
# #         elseif T == DECLARATIONTOKEN
# #             push!(doc.prolog, make_declaration(s))
# #         elseif T == COMMENTTOKEN
# #             push!(doc.prolog, make_comment(s))
# #         else  # root node
# #             doc.root = Element(get_tag(s), get_attributes(s))
# #             add_children!(doc.root, o, "</$(tag(doc.root))>")
# #         end
# #     end
# # end

# # # until = closing tag e.g. `</Name>`
# # function add_children!(e::Element, o::XMLTokenIterator, until::String)
# #     s = ""
# #     c = children(e)
# #     while s != until
# #         next = iterate(o, -1)  # if state == 0, io will get reset to original position
# #         isnothing(next) && break
# #         T, s = next[1]
# #         if T == COMMENTTOKEN
# #             push!(c, make_comment(s))
# #         elseif T == CDATATOKEN
# #             push!(c, make_cdata(s))
# #         elseif T == ELEMENTSELFCLOSEDTOKEN
# #             push!(c, make_element(s))
# #         elseif T == ELEMENTTOKEN
# #             child = make_element(s)
# #             add_children!(child, o, "</$(tag(child))>")
# #             push!(c, child)
# #         elseif T == TEXTTOKEN
# #             push!(c, s)
# #         end
# #     end
# # end

# # #-----------------------------------------------------------------------------# Node
# # include("node.jl")

end
