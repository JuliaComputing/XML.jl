module XML

using OrderedCollections: OrderedDict
import AbstractTrees: print_tree, printnode, children
using Dates

export Document, DTD, Declaration, Comment, CData, Element,
    children, tag, attributes

#-----------------------------------------------------------------------------# escape/unescape
escape_chars = ['&' => "&amp;", '"' => "&quot;", ''' => "&#39;", '<' => "&lt;", '>' => "&gt;"]
escape(x::AbstractString) = replace(x, escape_chars...)
unescape(x::AbstractString) = replace(x, reverse.(escape_chars)...)


#-----------------------------------------------------------------------------# XMLTokenIterator
@enum(TokenType,
    UNKNOWNTOKEN,           # ???
    DTDTOKEN,               # <!DOCTYPE ...>
    DECLARATIONTOKEN,       # <?xml attributes... ?>
    COMMENTTOKEN,           # <!-- ... -->
    CDATATOKEN,             # <![CDATA[...]]>
    ELEMENTTOKEN,           # <NAME attributes... >
    ELEMENTSELFCLOSEDTOKEN, # <NAME attributes... />
    ELEMENTCLOSETOKEN,      # </NAME>
    TEXTTOKEN               # text between a '>' and a '<'
)

mutable struct XMLTokenIterator{IOT <: IO}
    io::IOT
    start_pos::Int64  # position(io) always returns Int64?
    buffer::IOBuffer
end
XMLTokenIterator(io::IO) = XMLTokenIterator(io, position(io), IOBuffer())

readchar(o::XMLTokenIterator) = (c = read(o.io, Char); write(o.buffer, c); c)
reset(o::XMLTokenIterator) = seek(o.io, o.start_pos)

function readuntil(o::XMLTokenIterator, char::Char)
    c = readchar(o)
    while c != char
        c = readchar(o)
    end
end
function readuntil(o::XMLTokenIterator, pattern::String)
    chars = collect(pattern)
    last_chars = similar(chars)
    while last_chars != chars
        for i in 1:(length(chars) - 1)
            last_chars[i] = last_chars[i+1]
        end
        last_chars[end] = readchar(o)
    end
end

function Base.iterate(o::XMLTokenIterator, state=0)
    state == 0 && seek(o.io, o.start_pos)
    pair = next_token(o)
    isnothing(pair) ? nothing : (pair, state+1)
end

function next_token(o::XMLTokenIterator)
    io = o.io
    buffer = o.buffer
    skipchars(isspace, io)
    eof(io) && return nothing
    foreach(_ -> readchar(o), 1:3)
    s = String(take!(buffer))
    skip(io, -3)
    pair = if startswith(s, "<!D") || startswith(s, "<!d")
        readuntil(o, '>')
        DTDTOKEN => String(take!(buffer))
    elseif startswith(s, "<![")
        readuntil(o, "]]>")
        CDATATOKEN => String(take!(buffer))
    elseif startswith(s, "<!-")
        readuntil(o, "-->")
        COMMENTTOKEN => String(take!(buffer))
    elseif startswith(s, "<?x")
        readuntil(o, "?>")
        DECLARATIONTOKEN => String(take!(buffer))
    elseif startswith(s, "</")
        readuntil(o, '>')
        ELEMENTCLOSETOKEN => String(take!(buffer))
    elseif startswith(s, "<")
        readuntil(o, '>')
        s = String(take!(buffer))
        t = endswith(s, "/>") ? ELEMENTSELFCLOSEDTOKEN : ELEMENTTOKEN
        t => s
    else
        readuntil(o, '<')
        skip(io, -1)
        TEXTTOKEN => unescape(rstrip(String(take!(buffer)[1:end-1])))
    end
    return pair
end


Base.eltype(::Type{<:XMLTokenIterator}) = Pair{TokenType, String}

Base.IteratorSize(::Type{<:XMLTokenIterator}) = Base.SizeUnknown()

Base.isdone(itr::XMLTokenIterator, state...) = eof(itr.io)

#-----------------------------------------------------------------------------# AbstractXMLNode
abstract type AbstractXMLNode end

Base.show(io::IO, ::MIME"text/plain", o::AbstractXMLNode) = showxml(io, o)
Base.show(io::IO, ::MIME"text/xml", o::AbstractXMLNode) = showxml(io, o)
Base.show(io::IO, ::MIME"application/xml", o::AbstractXMLNode) = showxml(io, o)

Base.write(io::IO, doc::AbstractXMLNode) = foreach(x -> showxml(io, x), children(doc))

function Base.:(==)(a::T, b::T) where {T <: AbstractXMLNode}
    all(getfield(a, f) == getfield(b, f) for f in fieldnames(T))
end

const INDENT = "    "

showxml(x; depth=0) = (io=IOBuffer(); showxml(io, x); print(String(take!(io))))

# assumes '\n' occurs in String
function showxml(io::IO, x::String; depth=0)
    whitespace = INDENT^depth
    for row in split(x, keepempty=false)
        println(io)
        startswith(row, whitespace) ?
            printstyled(io, escape(row), color=:light_black) :
            printstyled(io, whitespace, escape(row), color=:light_black)
    end
end


#-----------------------------------------------------------------------------# DTD
# TODO: all the messy details of DTD.  For now, just dump everything into `text`
struct DTD <: AbstractXMLNode
    text::String
end
showxml(io::IO, o::DTD; depth=0) = print(io, INDENT^depth, "<!DOCTYPE ", o.text, '>')


#-----------------------------------------------------------------------------# Declaration
mutable struct Declaration <: AbstractXMLNode
    tag::String
    attributes::OrderedDict{Symbol, String}
end
function showxml(io::IO, o::Declaration; depth=0)
    print(io, INDENT ^ depth, "<?", o.tag)
    print_attributes(io, o)
    print(io, "?>")
end
attributes(o::Declaration) = o.attributes

#-----------------------------------------------------------------------------# CData
mutable struct CData <: AbstractXMLNode
    text::String
end
showxml(io::IO, o::CData; depth=0) = printstyled(io, INDENT ^ depth, "<![CDATA[", o.text, "]]>", color=:light_black)


#-----------------------------------------------------------------------------# Comment
mutable struct Comment <: AbstractXMLNode
    text::String
end
showxml(io::IO, o::Comment; depth=0) = printstyled(io, INDENT ^ depth, "<!-- ", escape(o.text), " -->", color=:light_black)

#-----------------------------------------------------------------------------# Element
mutable struct Element <: AbstractXMLNode
    tag::String
    attributes::OrderedDict{Symbol, String}
    children::Vector{Union{CData, Comment, Element, String}}
    function Element(tag="UNDEF", attributes=OrderedDict{Symbol,String}(), children=Union{CData, Comment, Element, String}[])
        new(tag, attributes, children)
    end
end
function h(tag::String, children...; attrs...)
    attributes = OrderedDict{Symbol,String}(k => string(v) for (k,v) in pairs(attrs))
    Element(tag, attributes, collect(children))
end
function showxml(io::IO, o::Element; depth=0)
    print(io, INDENT ^ depth, '<')
    printstyled(io, tag(o), color=:light_cyan)
    print_attributes(io, o)
    n = length(children(o))
    if n == 0
        print(io, "/>")
    elseif n == 1 && children(o)[1] isa String
        s = children(o)[1]
        print(io, '>')
        if occursin('\n', s)
            showxml(io, s, depth=depth+1)
            print(io, '\n', INDENT ^ depth, "</")
        else
            printstyled(io, escape(children(o)[1]), color=:light_black)
            print(io, "</")
        end
        printstyled(io, tag(o), color=:light_cyan)
        print(io, '>')
    else
        print(io, '>')
        foreach(x -> (println(io); showxml(io, x; depth=depth+1)), children(o))
        print(io, '\n', INDENT^depth, "</")
        printstyled(io, tag(o), color=:light_cyan)
        print(io, '>')
    end
end

Base.show(io::IO, o::Element) = print_tree(io, o)

function printnode(io::IO, o::Element, color=:light_cyan)
    print(io, '<')
    printstyled(io, tag(o), color=color)
    print_attributes(io, o)
    n = length(children(o))
    if n == 0
        print(io, "/>")
    else
        print(io, '>')
        printstyled(io, " (", length(children(o)), n > 1 ? " children)" : " child)", color=:light_black)
    end
end

function print_attributes(io::IO, o::AbstractXMLNode)
    foreach(pairs(attributes(o))) do (k,v)
        printstyled(io, ' ', k, '='; color=:green)
        printstyled(io, '"', v, '"'; color=:light_green)
    end
end

children(o::Element) = getfield(o, :children)
tag(o::Element) = getfield(o, :tag)
attributes(o::Element) = getfield(o, :attributes)

Base.getindex(o::Element, i::Integer) = children(o)[i]
Base.lastindex(o::Element) = lastindex(children(o))
Base.setindex!(o::Element, val::Element, i::Integer) = setindex!(children(o), val, i)

Base.getproperty(o::Element, x::Symbol) = attributes(o)[x]
Base.setproperty!(o::Element, x::Symbol, val) = (attributes(o)[x] = string(val))
Base.propertynames(o::Element) = collect(keys(attributes(o)))



#-----------------------------------------------------------------------------# Document
mutable struct Document <: AbstractXMLNode
    prolog::Vector{Union{Comment, Declaration, DTD}}
    root::Element
    Document(prolog=Union{Comment,Declaration,DTD}[], root=Element()) = new(prolog, root)
end

function Document(o::XMLTokenIterator)
    doc = Document()
    populate!(doc, o)
    return doc
end

Document(file::String) = open(io -> Document(XMLTokenIterator(io)), file, "r")

Base.show(io::IO, o::Document) = print_tree(io, o)
printnode(io::IO, o::Document) = print(io, "XML.Document")

children(o::Document) = (o.prolog..., o.root)

showxml(io::IO, o::Document; depth=0) = foreach(x -> (showxml(io, x), println(io)), children(o))


#-----------------------------------------------------------------------------# makers (AbstractXMLNode from a token)
make_dtd(s) = DTD(replace(s, "<!doctype " => "", "<!DOCTYPE " => "", '>' => ""))
make_declaration(s) = Declaration(get_tag(s), get_attributes(s))
make_comment(s) = Comment(replace(s, "<!-- " => "", " -->" => ""))
make_cdata(s) = CData(replace(s, "<![CDATA[" => "", "]]>" => ""))
make_element(s) = Element(get_tag(s), get_attributes(s))

get_tag(x) = x[findfirst(r"[a-zA-z][^\s>/]*", x)]  # Matches: (any letter) → (' ', '/', '>')

function get_attributes(x)
    out = OrderedDict{Symbol,String}()
    rng = findfirst(r"(?<=\s).*\"", x)
    isnothing(rng) && return out
    s = x[rng]
    kys = (m.match for m in eachmatch(r"[a-zA-Z][a-zA-Z\.-_]*(?=\=)", s))
    vals = (m.match for m in eachmatch(r"(?<=(\=\"))[^\"]*", s))
    foreach(zip(kys,vals)) do (k,v)
        out[Symbol(k)] = v
    end
    out
end



#-----------------------------------------------------------------------------# populate!
function populate!(doc::Document, o::XMLTokenIterator)
    for (T, s) in o
        if T == DTDTOKEN
            push!(doc.prolog, make_dtd(s))
        elseif T == DECLARATIONTOKEN
            push!(doc.prolog, make_declaration(s))
        elseif T == COMMENTTOKEN
            push!(doc.prolog, make_comment(s))
        else  # root node
            doc.root = Element(get_tag(s), get_attributes(s))
            add_children!(doc.root, o, "</$(tag(doc.root))>")
        end
    end
end

# until = closing tag e.g. `</Name>`
function add_children!(e::Element, o::XMLTokenIterator, until::String)
    s = ""
    c = children(e)
    while s != until
        next = iterate(o, -1)  # if state == 0, io will get reset to original position
        isnothing(next) && break
        T, s = next[1]
        if T == COMMENTTOKEN
            push!(c, make_comment(s))
        elseif T == CDATATOKEN
            push!(c, make_cdata(s))
        elseif T == ELEMENTSELFCLOSEDTOKEN
            push!(c, make_element(s))
        elseif T == ELEMENTTOKEN
            child = make_element(s)
            add_children!(child, o, "</$(tag(child))>")
            push!(c, child)
        elseif T == TEXTTOKEN
            push!(c, s)
        end
    end
end

end
