module XML

using OrderedCollections: OrderedDict
using Mmap
using Tables
using AbstractTrees: AbstractTrees, children

export Node, NodeType, children

#-----------------------------------------------------------------------------# escape/unescape
escape_chars = ['&' => "&amp;", '"' => "&quot;", ''' => "&#39;", '<' => "&lt;", '>' => "&gt;"]
escape(x::AbstractString) = replace(x, escape_chars...)
unescape(x::AbstractString) = replace(x, reverse.(escape_chars)...)

#-----------------------------------------------------------------------------# NodeType
"""
    NodeType:
    - DOCUMENT_NODE         # prolog & root ELEMENT_NODE
    - DTD_NODE              # <!DOCTYPE ...>
    - DECLARATION_NODE      # <?xml attributes... ?>
    - COMMENT_NODE          # <!-- ... -->
    - CDATA_NODE            # <![CDATA[...]]>
    - ELEMENT_NODE          # <NAME attributes... > children... </NAME>
    - TEXT_NODE             # text
    - UNKNOWN_NODE          # unknown
"""
@enum(NodeType, DOCUMENT_NODE, DTD_NODE, DECLARATION_NODE, COMMENT_NODE, CDATA_NODE,
    ELEMENT_NODE, TEXT_NODE, UNKNOWN_NODE)

#-----------------------------------------------------------------------------# XMLToken
"""
    XMLToken (an abuse of the word token, used as a superset of NodeType):
    TOK_TEXT                    # text
    TOK_COMMENT                 # <!-- ... -->
    TOK_CDATA                   # <![CDATA[...]]>
    TOK_DECLARATION             # <?xml attributes... ?>
    TOK_DTD                     # <!DOCTYPE ...>
    TOK_START_ELEMENT           # <NAME attributes... >
    TOK_END_ELEMENT             # </NAME>
    TOK_SELF_CLOSED_ELEMENT     # <NAME attributes... />
    TOK_UNKNOWN                 # Something to initilize with
"""
@enum(XMLToken, TOK_TEXT, TOK_COMMENT, TOK_CDATA, TOK_DECLARATION, TOK_DTD,
    TOK_START_ELEMENT, TOK_END_ELEMENT, TOK_SELF_CLOSED_ELEMENT, TOK_UNKNOWN)

#-----------------------------------------------------------------------------# Tokens
struct Tokens
    filename::String
    data::Vector{UInt8}
    Tokens(filename::String) = new(filename, Mmap.mmap(filename))
end
Tables.rows(o::Tokens) = o
Tables.schema(o::Tokens) = Tables.Schema(fieldnames(TokenData), fieldtypes(TokenData))

Base.IteratorSize(::Type{Tokens}) = Base.SizeUnknown()
Base.eltype(::Type{Tokens}) = TokenData
Base.isdone(o::Tokens, pos) = pos ≥ length(o.data)

function Base.iterate(o::Tokens, state = init(o))
    n = next(state)
    isnothing(n) && return nothing
    return n, n
end

#-----------------------------------------------------------------------------# TokenData
struct TokenData
    tok::XMLToken
    depth::Int
    next_depth::Int  # This will be wrong sometimes (ignored by ==)
    pos::Int
    len::Int
    data::Vector{UInt8} # also ignored by ==
end
function Base.show(io::IO, o::TokenData)
    print(io, o.tok)
    printstyled(io, " (depth=", o.depth, ", ", "pos=", o.pos, ") : "; color=:light_black)
    printstyled(io, String(o.data[o.pos:o.pos + o.len]); color=:light_green)
end
function Base.:(==)(a::TokenData, b::TokenData)
    a.tok == b.tok && a.depth == b.depth && a.pos == b.pos && a.len == b.len
end
String(o::TokenData) = String(o.data[o.pos:o.pos + o.len])

init(o::Tokens) = TokenData(TOK_UNKNOWN, 0, 1, 0, 0, o.data)

function next(o::TokenData)
    i = o.pos + o.len + 1
    depth = o.next_depth
    data = o.data
    i = findnext(x -> !isspace(Char(x)), data, i)  # skip insignificant whitespace
    isnothing(i) && return nothing
    c = Char(o.data[i])
    j = i + 1
    tok = TOK_UNKNOWN
    next_depth = depth
    if c !== '<'
        tok = TOK_TEXT
        j = findnext(==(UInt8('<')), data, i) - 1
    elseif c === '<'
        c2 = Char(o.data[i + 1])
        if c2 === '!'
            c3 = Char(o.data[i + 2])
            if c3 === '-'
                i += 1
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
            next_depth -= 1
        else
            j = findnext(==(UInt8('>')), data, i)
            if data[j-1] === UInt8('/')
                tok = TOK_SELF_CLOSED_ELEMENT
            else
                next_depth += 1
                tok = TOK_START_ELEMENT
            end
        end
    end
    tok === TOK_UNKNOWN && error("Token isn't identified: $(String(data[i:j]))")
    return TokenData(tok, depth, next_depth, i, j - i, data)
end

function prev(o::TokenData)
    j = o.pos - 1
    j < 1 && return nothing
    (; depth, data) = o
    next_depth = depth
    j = findprev(x -> !isspace(Char(x)), data, j)  # skip insignificant whitespace
    isnothing(j) && return nothing
    c = Char(o.data[j])
    i = j - 1
    tok = TOK_UNKNOWN
    if c !== '>' # text
        tok = TOK_TEXT
        i = findprev(==(UInt8('>')), data, j) + 1
    elseif c === '>'
        c2 = Char(o.data[j - 1])
        if c2 === '-'
            tok = TOK_COMMENT
            i = findprev(Vector{UInt8}("<--"), data, j)[1]
        elseif c2 === ']'
            tok = TOK_CDATA
            i = findprev(Vector{UInt8}("<![CDATA["), data, j)[1]
        elseif c2 === '?'
            tok = TOK_DECLARATION
            i = findprev(Vector{UInt8}("<?xml"), data, j)[1]
        else
            i = findprev(==(UInt8('<')), data, j)
            char = Char(data[i+1])
            if char === '/'
                tok = TOK_END_ELEMENT
            elseif char === '!'
                tok = TOK_DTD
            elseif isletter(char) || char === '_'
                tok = TOK_START_ELEMENT
            else
                error("Should be unreachable.  Unexpected token: <$char ... $c3$c2$c1>.")
            end
        end
    else
        error("Unreachable reached in XML.prev")
    end
    nexttok = o.tok
    if nexttok === TOK_END_ELEMENT
        if tok !== TOK_START_ELEMENT
            depth += 1
        end
    elseif tok === TOK_START_ELEMENT
        depth -= 1
    end
    return TokenData(tok, depth, next_depth, i, j - i, data)
end


#-----------------------------------------------------------------------------# Lazy
struct LazyNode
    data::TokenData
end
LazyNode(t::Tokens) = LazyNode(init(t))
LazyNode(filename::AbstractString) = LazyNode(Tokens(filename))

Base.get(o::LazyNode) = RowNode(o.data)

function next(o::LazyNode)
    x = next(o.data)
    isnothing(x) ? nothing : LazyNode(x)
end
function prev(o::LazyNode)
    x = prev(o.data)
    isnothing(x) ? nothing : LazyNode(x)
end

function Base.show(io::IO, o::LazyNode)
    print(io, "LazyNode: ")
    show(io, get(o))
end
function AbstractTrees.children(o::LazyNode)
    depth = o.data.depth
    out = LazyNode[]
    x = o
    while !isnothing(x)
        x = next(x)
        isnothing(x) && break
        x.data.tok === TOK_END_ELEMENT && continue
        x.data.depth == depth && break
        x.data.depth == depth + 1 && push!(out, x)
    end
    return out
end
AbstractTrees.nodevalue(o::LazyNode) = get(o)

function AbstractTrees.parent(o::LazyNode)
    depth = o.data.depth
    x = prev(o)
    while !isnothing(x)
        x.data.depth == depth - 1 && return x
        x = prev(x)
    end
    return nothing
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
function RowNode(t::TokenData)
    (; tok, pos, len, depth) = t
    pos === 0 && return RowNode(0, DOCUMENT_NODE, nothing, nothing, nothing)
    data = view(t.data, pos:pos+len)
    @views if tok === TOK_TEXT  # text
        return RowNode(depth, TEXT_NODE, nothing, nothing, unescape(String(data)))
    elseif tok === TOK_COMMENT  # <!-- ... -->
        return RowNode(depth, COMMENT_NODE, nothing, nothing, String(data[4:end-3]))
    elseif tok === TOK_CDATA  # <![CDATA[...]]>
        return RowNode(depth, CDATA_NODE, nothing, nothing, String(data[10:end-3]))
    elseif tok === TOK_DECLARATION  # <?xml attributes... ?>
        rng = 7:length(data) - 2
        attributes = get_attributes(data[rng])
        return RowNode(depth, DECLARATION_NODE, nothing, attributes, nothing)
    elseif  tok === TOK_DTD  # <!DOCTYPE ...>
        return RowNode(depth, DTD_NODE, nothing, nothing, String(data[10:end-1]))
    elseif tok === TOK_START_ELEMENT  # <NAME attributes... >
        tag, i = get_name(data, 2)
        i = findnext(x -> isletter(Char(x)) || x === UInt8('_'), data, i)
        attributes = isnothing(i) ? nothing : get_attributes(data[i:end-1])
        return RowNode(depth, ELEMENT_NODE, tag, attributes, nothing)
    elseif tok === TOK_END_ELEMENT  # </NAME>
        return nothing
    elseif  tok === TOK_SELF_CLOSED_ELEMENT  # <NAME attributes... />
        tag, i = get_name(data, 2)
        i = findnext(x -> isletter(Char(x)) || x === UInt8('_'), data, i)
        attributes = isnothing(i) ? nothing : get_attributes(data[i:end-2])
        return RowNode(depth, ELEMENT_NODE, tag, attributes, nothing)
    else
        error("Unhandled token: $tok.")
    end
end

AbstractTrees.children(o::RowNode) = missing

Base.show(io::IO, o::RowNode) = _show_node(io, o)

Base.IteratorSize(::Type{Rows}) = Base.SizeUnknown()
Base.eltype(::Type{Rows}) = RowNode
Base.isdone(o::Rows, pos) = isdone(o.file, pos)

function Base.iterate(o::Rows, state = init(o.tokens))
    n = next(state)
    isnothing(n) && return nothing
    n.tok === TOK_END_ELEMENT && return iterate(o, n)
    return RowNode(n), n
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
Base.@kwdef struct Node
    nodetype::NodeType
    tag::Union{Nothing, String} = nothing
    attributes::Union{Nothing, OrderedDict{String, String}} = nothing
    value::Union{Nothing, String} = nothing
    children::Union{Nothing, Vector{Node}} = nothing
    depth::Int = 0
end
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

function Node((; depth, nodetype, tag, attributes, value)::RowNode)
    Node(; depth, nodetype, tag, attributes, value)
end
Node(o::TokenData) = Node(RowNode(o))

function Base.:(==)(a::Node, b::Node)
    a.nodetype == b.nodetype &&
    a.tag == b.tag &&
    a.attributes == b.attributes &&
    a.value == b.value && (
        (isnothing(a.children) && isnothing(b.children)) ||
        (isnothing(a.children) && isempty(b.children)) ||
        (isempty(a.children) && isnothing(b.children)) ||
        all(ai == bi for (ai,bi) in zip(a.children, b.children))
    )
end

# function element(nodetype::NodeType, tag = nothing; attributes...)
#     attributes = isempty(attributes) ?
#         nothing :
#         OrderedDict(string(k) => string(v) for (k,v) in attributes)
#     Node(; nodetype, tag, attributes)
# end

Base.getindex(o::Node, i::Integer) = o.children[i]
Base.setindex!(o::Node, val, i::Integer) = o.children[i] = Node(val)
Base.lastindex(o::Node) = lastindex(o.children)

Base.push!(a::Node, b::Node) = push!(a.children, b)

AbstractTrees.children(o::Node) = isnothing(o.children) ? [] : o.children

Base.show(io::IO, o::Node) = _show_node(io, o)

#-----------------------------------------------------------------------------# read
read(filename::AbstractString) = Node(Tokens(filename))
read(io::IO) = Node(Tokens("__UKNOWN_FILE__", read(io)))

Node(filename::String) = Node(Tokens(filename))

function Node(t::Tokens)
    doc = Node(; nodetype=DOCUMENT_NODE, children=[])
    stack = [doc]
    for row in Rows(t)
        temp = Node(row)
        node = Node(temp; children = row.nodetype === ELEMENT_NODE ? [] : nothing)
        filter!(x -> x.depth < node.depth, stack)
        push!(stack[end], node)
        push!(stack, node)
    end
    return doc
end

#-----------------------------------------------------------------------------# printing
function _show_node(io::IO, o)
    printstyled(io, lpad("$(o.depth)", 2o.depth), ':', o.nodetype, ' '; color=:light_green)
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

#-----------------------------------------------------------------------------# write_xml
write(x::Node) = (io = IOBuffer(); write(io, x); String(take!(io)))

write(filename::AbstractString, x::Node) = open(io -> write(io, x), filename, "w")

function write(io::IO, x::Node; indent = "   ")
    padding = indent ^ max(0, x.depth - 1)
    print(io, padding)
    if x.nodetype === TEXT_NODE
        print(io, escape(x.value))
    elseif x.nodetype === ELEMENT_NODE
        print(io, '<', x.tag)
        _print_attrs(io, x)
        print(io, isnothing(x.children) ? '/' : "", '>')
        single_text_child = !isnothing(x.children) && length(x.children) == 1 && x.children[1].nodetype === TEXT_NODE
        if single_text_child
            write(io, only(x.children); indent="")
            print(io, "</", x.tag, '>')
        elseif !isnothing(x.children)
            println(io)
            foreach(AbstractTrees.children(x)) do child
                write(io, child; indent)
                println(io)
            end
            print(io, padding, "</", x.tag, '>')
        end
    elseif x.nodetype === DTD_NODE
        print(io, "<!DOCTYPE", x.value, '>')
    elseif x.nodetype === DECLARATION_NODE
        print(io, "<?xml")
        _print_attrs(io, x)
        print(io, "?>")
    elseif x.nodetype === COMMENT_NODE
        print(io, "<!--", x.value, "-->")
    elseif x.nodetype === CDATA_NODE
        print(io, "<![CDATA[", x.value, "]]>")
    elseif x.nodetype === DOCUMENT_NODE
        foreach(AbstractTrees.children(x)) do child
            write(io, child; indent)
            println(io)
        end
    else
        error("Unreachable case reached during XML.write")
    end
end

end
