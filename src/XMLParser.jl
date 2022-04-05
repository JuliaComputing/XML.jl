module XMLParser

using OrderedCollections: OrderedDict

#-----------------------------------------------------------------------------# Comment
mutable struct Comment
    data::String
end
function Base.show(io::IO, o::Comment)
    depth = get(io, :depth, 0)
    printstyled(io, "  " ^ depth, "<!-- ", o.data, " -->\n", color=:light_black)
end

#-----------------------------------------------------------------------------# CData
mutable struct CData
    data::String
end
function Base.show(io::IO, o::CData)
    depth = get(io, :depth, 0)
    printstyled(io, "  " ^ depth, "<![CDATA[", o.data, "]]>\n", color=:light_black)
end

#-----------------------------------------------------------------------------# Element
mutable struct Element
    tag::String
    attrs::OrderedDict{String,String}
    children::Vector
    closed::Bool  # If false, must be a prolog element like `<?xml`, `<!doctype`
    function Element(tag="", attrs=OrderedDict{String,String}(), children = []; closed=true)
        new(tag, attrs, children, closed)
    end
end
function Base.show(io::IO, o::Element)
    depth = get(io, :depth, 1)
    indent = "  " ^ (depth - 1)
    p(x...) = printstyled(io, x...; color=depth)
    p(indent, '<', o.tag, (" $k=$(repr(v))" for (k,v) in o.attrs)...)
    if length(o.children) == 0 && o.closed
        p(" />")
    elseif !o.closed
        p(">")
    elseif length(o.children) == 1 && o.children[1] isa AbstractString
        child = o.children[1]
        p('>')
        printstyled(io, child, color=depth+1)
        p(occursin('\n', child) ? "\n$indent</" : "</", o.tag, ">\n")
    else
        p(">\n")
        for child in o.children
            child isa AbstractString ?
                p(indent, child, '\n') :
                print(IOContext(io, :depth => depth + 1), child)
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


function parsefile(io::Union{String,IO})
    prolog = Element[]
    is_prolog = true
    depth = 0
    path = []
    for (i, x) in enumerate(readeach(io, '<', keep=false))
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

get_tag(s::AbstractString) = try
    s[findfirst(r"([^\s>]+)", s)]
catch
    error("tag not found in: $(repr(s))")
end

function get_attrs(s::AbstractString)
    d = OrderedDict{String,String}()
    rng = findfirst(r"\s.*>", s)
    isnothing(rng) && return d
    for line in Iterators.split(s[rng], ' ', keepempty=false)
        k, v = split(line, '=', keepempty=false)
        d[k] = strip(v[findfirst(r"(?<=\").*(?=\")", v)])
    end
    return d
end

function get_content(s::AbstractString)
    if endswith(s, '>')
        return []
    else
        rng = findfirst(r"(?<=\>)[^\<]*", s)
        return Any[s[rng]]
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
