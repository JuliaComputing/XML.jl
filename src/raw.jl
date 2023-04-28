#-----------------------------------------------------------------------------# RawType
"""
    RawType:
    - RawText                    # text
    - RawComment                 # <!-- ... -->
    - RawCData                   # <![CData[...]]>
    - RawDeclaration             # <?xml attributes... ?>
    - RawProcessingInstruction  # <?NAME attributes... ?>
    - RawDTD                     # <!DOCTYPE ...>
    - RawElementOpen            # <NAME attributes... >
    - RawElementClose           # </NAME>
    - RawElementSelfClosed     # <NAME attributes... />
    - RawDocument                # Something to initilize with (not really used)
"""
@enum(RawType, RawDocument, RawText, RawComment, RawCData, RawProcessingInstruction,
    RawDeclaration, RawDTD, RawElementOpen, RawElementClose, RawElementSelfClosed)

@inline nodetype(x::RawType) =
    x === RawElementOpen            ? Element :
    x === RawElementClose           ? Element :
    x === RawElementSelfClosed      ? Element :
    x === RawText                   ? Text :
    x === RawComment                ? Comment :
    x === RawCData                  ? CData :
    x === RawDeclaration            ? Declaration :
    x === RawDTD                    ? DTD :
    x === RawProcessingInstruction  ? ProcessingInstruction :
    x === RawDocument               ? Document :
    nothing

#-----------------------------------------------------------------------------# Raw
"""
    Raw(filename::String)

Create an iterator over raw chunks of data in an XML file.  Each chunk of data represents one of:

    - RawDocument                # Only used to initialize the iterator state.
    - RawText                    # text
    - RawComment                 # <!-- ... -->
    - RawCData                   # <![CData[...]]>
    - RawDeclaration             # <?xml attributes... ?>
    - RawProcessingInstruction  # <?NAME attributes... ?>
    - RawDTD                     # <!DOCTYPE ...>
    - RawElementOpen            # <NAME attributes... >
    - RawElementClose           # </NAME>
    - RawElementSelfClosed     # <NAME attributes... />

Useful functions:

    - view(o::Raw) --> view of the Vector{UInt8} chunk.
    - String(o::Raw) --> String of the chunk.
    - next(o::Raw) --> Raw of the next chunk (or `nothing`).
    - prev(o::Raw) --> Raw of the previous chunk (or `nothing`).
    - tag(o::Raw) --> String of the tag name (or `nothing`).
    - attributes(o::Raw) --> Dict{String, String} of the attributes (or `nothing`).
    - value(o::Raw) --> String of the value (or `nothing`).
    - children(o::Raw) --> Vector{Raw} of the children (or `nothing`).
    - parent(o::Raw) --> Raw of the parent (or `nothing`)
    - depth(o::Raw) --> Int of the depth of the node in the XML DOM.
"""
struct Raw
    type::RawType
    depth::Int
    pos::Int
    len::Int
    data::Vector{UInt8}
end
Raw(data::Vector{UInt8}) = Raw(RawDocument, 0, 0, 0, data)

Base.read(filename::String, ::Type{Raw}) = isfile(filename) ?
    Raw(Mmap.mmap(filename)) :
    error("File \"$filename\" does not exist.")

Base.read(io::IO, ::Type{Raw}) = Raw(read(io))

parse(x::AbstractString, ::Type{Raw}) = Raw(Vector{UInt8}(x))

# Mostly for debugging
Base.peek(o::Raw, n::Int) = String(@view(o.data[o.pos + o.len + 1:min(end, o.pos + o.len + n + 1)]))

function Base.show(io::IO, o::Raw)
    print(io, o.type, ':', o.depth, " (pos=", o.pos, ", len=", o.len, ")")
    o.len > 0 && printstyled(io, ": ", String(o); color=:light_green)
end
function Base.:(==)(a::Raw, b::Raw)
    a.type == b.type && a.depth == b.depth && a.pos == b.pos && a.len == b.len && a.data === b.data
end

Base.view(o::Raw) = view(o.data, o.pos:o.pos + o.len)
String(o::Raw) = String(view(o))

Base.IteratorSize(::Type{Raw}) = Base.SizeUnknown()
Base.eltype(::Type{Raw}) = Raw

function Base.iterate(o::Raw, state=o)
    n = next(state)
    return isnothing(n) ? nothing : (n, n)
end

is_node(o::Raw) = o.type !== RawElementClose
xml_nodes(o::Raw) = Iterators.Filter(is_node, o)

#-----------------------------------------------------------------------------# get_name
is_name_start_char(x::UInt8) = x in UInt8('A'):UInt8('Z') || x in UInt8('a'):UInt8('z') || x == UInt8('_')
is_name_char(x::UInt8) = is_name_start_char(x) || x in UInt8('0'):UInt8('9') || x == UInt8('-') || x == UInt8('.') || x == UInt8(':')

name_start(data, i) = findnext(is_name_start_char, data, i)
name_stop(data, i) = findnext(!is_name_char, data, i) - 1

function get_name(data, i)
    i = name_start(data, i)
    j = name_stop(data, i)
    @views String(data[i:j]), j + 1
end

#-----------------------------------------------------------------------------# get_attributes
# starting at position i, return attributes up until the next '>' or '?' (DTD)
function get_attributes(data, i, j)
    i = name_start(data, i)
    i > j && return nothing
    out = Dict{String, String}()
    while !isnothing(i) && i < j
        key, i = get_name(data, i)
        # get quotechar the value is wrapped in (either ' or ")
        i = findnext(x -> x === UInt8('"') || x === UInt8('''), data, i + 1)
        quotechar = data[i]
        i2 = findnext(==(quotechar), data, i + 1)
        @views value = String(data[i+1:i2-1])
        out[key] = value
        i = name_start(data, i2)
    end
    return out
end


#-----------------------------------------------------------------------------# interface
"""
    nodetype(node) --> XML.NodeType

Return the `XML.NodeType` of the node.
"""
nodetype(o::Raw) = nodetype(o.type)

"""
    tag(node) --> String or Nothing

Return the tag name of `Element` and `PROCESESSING_INSTRUCTION` nodes.
"""
function tag(o::Raw)
    o.type ∉ [RawElementOpen, RawElementClose, RawElementSelfClosed, RawProcessingInstruction] && return nothing
    return get_name(o.data, o.pos + 1)[1]
end

"""
    attributes(node) --> Dict{String, String} or Nothing

Return the attributes of `Element`, `Declaration`, or `ProcessingInstruction` nodes.
"""
function attributes(o::Raw)
    if o.type === RawElementOpen || o.type === RawElementSelfClosed || o.type === RawProcessingInstruction
        i = o.pos
        i = name_start(o.data, i)
        i = name_stop(o.data, i)
        get_attributes(o.data, i + 1, o.pos + o.len)
    elseif o.type === RawDeclaration
        get_attributes(o.data, o.pos + 6, o.pos + o.len)
    else
        nothing
    end
end

"""
    value(node) --> String or Nothing

Return the value of `Text`, `CData`, `Comment`, or `DTD` nodes.
"""
function value(o::Raw)
    if o.type === RawText
        String(o)
    elseif o.type === RawCData
        String(view(o.data, o.pos + length("<![CData[") : o.pos + o.len - 3))
    elseif o.type === RawComment
        String(view(o.data, o.pos + length("<!--") : o.pos + o.len - 3))
    elseif o.type === RawDTD
        String(view(o.data, o.pos + length("<!DOCTYPE ") : o.pos + o.len - 1))
    else
        nothing
    end
end

"""
    children(node) --> Vector{typeof(node)}

Return the children the node.  Will only be nonempty for `Element` and `Document` nodes.
"""
function children(o::Raw)
    if o.type === RawElementOpen || o.type === RawDocument
        depth = o.depth
        out = Raw[]
        for item in xml_nodes(o)
            item.depth == depth + 1 && push!(out, item)
            item.depth == depth && break
            o.type === RawDocument && item.depth == 2 && break # break if we've seen the doc root
        end
        out
    else
        Raw[]
    end
end

"""
    parent(node) --> typeof(node), Nothing

Return the parent of the node.  Will be `nothing` for `Document` nodes.  Not defined for `XML.Node`.
"""
function parent(o::Raw)
    depth = o.depth
    depth === 1 && return nothing
    p = prev(o)
    while p.depth >= depth
        p = prev(p)
    end
    return p
end


#-----------------------------------------------------------------------------# next Raw
isspace(x::UInt8) = Base.isspace(Char(x))

"""
    next(node) --> typeof(node) or Nothing

Return the next node in the document during depth-first traversal.  Depth-first is the order you
would visit nodes by reading top-down through an XML file.  Not defined for `XML.Node`.
"""
function next(o::Raw)
    i = o.pos + o.len + 1
    (; depth, data, type) = o
    i = findnext(!isspace, data, i)  # skip insignificant whitespace
    isnothing(i) && return nothing
    if type === RawElementOpen || type === RawDocument
        depth += 1
    end
    c = Char(o.data[i])
    j = i + 1
    if c !== '<'
        type = RawText
        j = findnext(==(UInt8('<')), data, i) - 1
        j = findprev(!isspace, data, j)   # "rstrip"
    elseif c === '<'
        c2 = Char(o.data[i + 1])
        if c2 === '!'
            c3 = Char(o.data[i + 2])
            if c3 === '-'
                type = RawComment
                j = findnext(Vector{UInt8}("-->"), data, i)[end]
            elseif c3 === '['
                type = RawCData
                j = findnext(Vector{UInt8}("]]>"), data, i)[end]
            elseif c3 === 'D'
                type = RawDTD
                j = findnext(==(UInt8('>')), data, i)
                while sum(==(UInt8('>')), data[i:j]) != sum(==(UInt8('<')), data[i:j])
                    j = findnext(==(UInt8('>')), data, j + 1)
                end
            end
        elseif c2 === '?'
            if get_name(data, i + 2)[1] == "xml"
                type = RawDeclaration
            else
                type = RawProcessingInstruction
            end
            j = findnext(Vector{UInt8}("?>"), data, i)[end]
        elseif c2 === '/'
            type = RawElementClose
            depth -= 1
            j = findnext(==(UInt8('>')), data, i)
        else
            j = findnext(==(UInt8('>')), data, i)
            if data[j-1] === UInt8('/')
                type = RawElementSelfClosed
            else
                type = RawElementOpen
            end
        end
    end
    return Raw(type, depth, i, j - i, data)
end

#-----------------------------------------------------------------------------# prev Raw
"""
    prev(node) --> typeof(node), Nothing, or Missing (only for XML.Node)

Return the previous node in the document during depth-first traversal.  Not defined for `XML.Node`.
"""
function prev(o::Raw)
    (; depth, data, type) = o
    type === RawDocument && return nothing
    j = o.pos - 1
    j = findprev(!isspace, data, j)  # skip insignificant whitespace
    isnothing(j) && return Raw(data)  # RawDocument
    c = Char(o.data[j])
    i = j - 1
    next_type = type
    if c !== '>' # text
        type = RawText
        i = findprev(==(UInt8('>')), data, j) + 1
        i = findnext(!isspace, data, i)  # "lstrip"
    elseif c === '>'
        c2 = Char(o.data[j - 1])
        if c2 === '-'
            type = RawComment
            i = findprev(Vector{UInt8}("<--"), data, j)[1]
        elseif c2 === ']'
            type = RawCData
            i = findprev(Vector{UInt8}("<![CData["), data, j)[1]
        elseif c2 === '?'
            i = findprev(Vector{UInt8}("<?"), data, j)[1]
            if get_name(data, i + 2)[1] == "xml"
                type = RawDeclaration
            else
                type = RawProcessingInstruction
            end
        else
            i = findprev(==(UInt8('<')), data, j)
            char = Char(data[i+1])
            if char === '/'
                type = RawElementClose
            elseif char === '!'
                type = DTD
            elseif isletter(char) || char === '_'
                type = Char(o.data[j - 2]) === '/' ? RawElementSelfClosed : RawElementOpen
            else
                error("Should be unreachable.  Unexpected data: <$char ... $c3$c2$c1>.")
            end
        end
    else
        error("Unreachable reached in XML.prev")
    end
    if type !== RawElementOpen && next_type === RawElementClose
        depth += 1
    elseif type == RawElementOpen && next_type !== RawElementClose
        depth -= 1
    end
    return Raw(type, depth, i, j - i, data)
end
