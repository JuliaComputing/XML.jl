module XMLFiles

using OrderedCollections: OrderedDict

export Comment, CData, Element

#-----------------------------------------------------------------------------# Comment
"""
    Comment(comment::String)

Displays in XML as `<!-- comment -->`.
"""
mutable struct Comment
    data::String
end
function Base.show(io::IO, o::Comment)
    depth = get(io, :depth, 0)
    printstyled(io, "  " ^ depth, "<!-- ", o.data, " -->\n", color=:light_black)
end

#-----------------------------------------------------------------------------# CData
"""
    CData(data::String)

Displays in XML as `![CDATA[data]]`.
"""
mutable struct CData
    data::String
end
function Base.show(io::IO, o::CData)
    depth = get(io, :depth, 0)
    printstyled(io, "  " ^ depth, "<![CDATA[", o.data, "]]>\n", color=:light_black)
end

#-----------------------------------------------------------------------------# Element
"""
    Element(tag::String, attrs = OrderedDict{String,String}(), children::Vector=[]; closed=true)

Create an XML element with the given `tag`, `attrs`, and `children`.  `closed` indicated whether the
tag needs to be closed (`false` is only allowed for prolog elements).

    (e::Element)(children...; attrs...)

Create a new XML element using an existing `Element` as a template, using copies of the template's `children`/`attrs`.
"""
mutable struct Element
    tag::String
    attrs::OrderedDict{String,String}
    children::Vector
    closed::Bool  # If false, must be a prolog element like `<?xml`, `<!doctype`
    function Element(tag::AbstractString="", attrs::OrderedDict{String,String}=OrderedDict{String,String}(), children::Vector = []; closed=true)
        new(tag, attrs, children, closed)
    end
end
Element(tag::AbstractString, children...; attrs...) = Element(tag, OrderedDict(string(k) => string(v) for (k,v) in attrs), collect(children))
(e::Element)(children...; attrs...) = Element(e.tag, merge(e.attrs, OrderedDict(string(k) => string(v) for (k,v) in attrs)), vcat(e.children, children...))
function Base.show(io::IO, o::Element)
    depth = get(io, :depth, 1)
    indent = "  " ^ (depth - 1)
    p(x...) = printstyled(io, x...; color=depth)
    p(indent, '<', o.tag, (" $k=$(repr(v))" for (k,v) in o.attrs)...)
    if length(o.children) == 0 && o.closed
        p(" />\n")
    elseif !o.closed
        p(">")
    elseif length(o.children) == 1 && o.children[1] isa AbstractString
        child = o.children[1]
        p('>')
        if occursin('\n', child)
            printstyled(io, '\n', "  " ^ (depth), child, color=depth+1)
            print(io, "\n$indent")
        else
            printstyled(io, child; color=depth+1)
        end
        p("</", o.tag, ">\n")
    else
        p(">\n")
        for child in o.children
            if child isa AbstractString
                startswith(indent, child) || print(io, "  " ^ depth)
                printstyled(io, indent, child, '\n', color=depth+1)
            else
                print(IOContext(io, :depth => depth + 1), child)
            end
        end
        p(indent, "</", o.tag, '>', '\n')
    end
end

#-----------------------------------------------------------------------------# Document
mutable struct Document
    prolog::Vector{Element}
    root::Element
end
function Base.show(io::IO, doc::Document)
    println(io, "XMLParser.Document\n")
    for o in doc.prolog
        println(io, o)
    end
    print(io, doc.root)
end

#-----------------------------------------------------------------------------# parse
# Possible ways for line to start:
# <?tag (prolog only)
# <!tag (prolog only)
# <!CDATA (CData)
# <!-- (Comment)
# /tag>
# content
function xml_from_itr(itr)
    prolog = Element[]
    is_prolog = true
    depth = 0
    path = Element[]
    for (i, x) in enumerate(itr)
        i == 1 && continue
        line = rstrip(x)
        # @info "Before: $i | $line | npath = $(length(path)) | depth = $depth"
        if is_prolog
            if startswith(line, "!--")
                push!(prolog, Comment(replace(line, "!-- " => "", "!--" => "", " -->" => "", "-->" => "")))
            elseif startswith(line, "![CDATA")
                push!(prolog, CData(line[findfirst(r"(?<=CDATA\[).*(?=\]\])", line)]))
            elseif startswith(line, '?') || startswith(line, '!')
                push!(prolog, Element(get_tag(line), get_attrs(line)))
            else # Root Element
                is_prolog = false
                depth = 1
                push!(path, Element(get_tag(line), get_attrs(line), get_content(line)))
            end
        else
            if startswith(line, "!--")
                push!(path[end].children, Comment(replace(line, "!-- " => "", "!--" => "", " -->" => "", "-->" => "")))
            elseif startswith(line, "![CDATA")
                push!(path[end].children, CData(line[findfirst(r"(?<=CDATA\[).*(?=\]\])", line)]))
            elseif startswith(line, '/')
                depth -= 1
            else
                depth += 1
                el = Element(get_tag(line), get_attrs(line), get_content(line))
                if length(path) < depth
                    push!(path[end].children, el)
                    push!(path, el)
                elseif length(path) == depth
                    path[depth] = el
                    push!(path[depth-1].children, el)
                elseif length(path) > depth
                    path = path[1:depth]
                    path[depth] = el
                    push!(path[depth-1].children, el)
                end
            end
        end
        # @info "After: $i | $line | npath = $(length(path)) | depth = $depth"
    end

    return Document(prolog, path[1])
end


parsefile(io::Union{AbstractString,IO}) = xml_from_itr(readeach(io, '<', keep=false))
parse(s::AbstractString) = xml_from_itr(split(s, '<', keepempty=false))

get_tag(s::AbstractString) = s[findfirst(r"([^\s>]+)", s)]

function get_attrs(s::AbstractString)
    d = OrderedDict{String,String}()
    rng = findfirst(r"\s.*>", s)
    isnothing(rng) && return d
    for line in Iterators.split(s[rng], ' ', keepempty=false)
        k, v = split(line, '=', keepempty=false)
        d[k] = v[findfirst(r"(?<=\").*(?=\")", v)]
    end
    return d
end

function get_content(s::AbstractString)
    if endswith(s, '>')
        return []
    else
        rng = findfirst(r"(?<=\>)[^\<]*", s)
        return Any[strip(s[rng])]
    end
end

#-----------------------------------------------------------------------------# ReadEach
struct ReadEach{IOT <: IO, C<:AbstractChar}
    stream::IOT
    ondone::Function
    keep::Bool
    char::C
    function ReadEach(stream::IO, char::C; ondone::Function=()->nothing, keep::Bool=false) where {C<:AbstractChar}
        new{typeof(stream), C}(stream, ondone, keep, char)
    end
end

function readeach(stream::IO=stdin; keep::Bool=false)
    ReadEach(stream, keep=keep)::ReadEach
end

function readeach(filename::AbstractString, char::AbstractChar; keep::Bool=false)
    s = open(filename)
    ReadEach(s, char, ondone=()->close(s), keep=keep)::ReadEach
end

function Base.iterate(itr::ReadEach, state=nothing)
    eof(itr.stream) && return (itr.ondone(); nothing)
    (readuntil(itr.stream, '<'; keep=itr.keep), nothing)
end

Base.eltype(::Type{<:ReadEach}) = String

Base.IteratorSize(::Type{<:ReadEach}) = SizeUnknown()

Base.isdone(itr::ReadEach, state...) = eof(itr.stream)


end
