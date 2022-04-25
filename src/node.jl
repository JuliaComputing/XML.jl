@enum(NodeType,
    DOCUMENT_NODE,          # prolog & root ELEMENT_NODE
    DTD_NODE,               # <!DOCTYPE ...>
    DECLARATION_NODE,       # <?xml attributes... ?>
    COMMENT_NODE,           # <!-- ... -->
    CDATA_NODE,             # <![CDATA[...]]>
    ELEMENT_NODE,           # <NAME attributes... >
)

#-----------------------------------------------------------------------------# Node
struct Node
    type::NodeType
    tag::Union{Nothing, String}
    attributes::Union{Nothing, Dict{Symbol, String}}
    children::Union{Nothing, Vector{Union{String, Node}}, String}
    Node(type, tag, attr, children::Nothing) = new(type, tag, attr, children)
    function Node(type, tag, attributes, children::Vector)
        new(type, tag, attributes, Vector{Union{String,Node}}(children))
    end
    function Node(type, tag, attributes, children::AbstractString)
        new(type, tag, attributes, String(children))
    end
end
function Base.:(==)(a::Node, b::Node)
    a.type == b.type &&
        a.tag == b.tag &&
        a.attributes == b.attributes &&
        a.children == b.children
end

Base.show(io::IO, o::Node) = showxml(io, o)

Base.write(io::IO, o::Node) = showxml(io, o)


document(children...) = Node(DOCUMENT_NODE, nothing, nothing, collect(children))
dtd(content::AbstractString) = Node(DTD_NODE, nothing, nothing, content)
declaration(; attrs...) = Node(DECLARATION_NODE, nothing, OrderedDict(k=>string(v) for (k,v) in pairs(attrs)), nothing)
comment(content::AbstractString) = Node(COMMENT_NODE, nothing, nothing, content)
cdata(content::AbstractString) = Node(CDATA_NODE, nothing, nothing, content)

m(tag::String, children...; attrs...) = Node(ELEMENT_NODE, tag, OrderedDict(k=>string(v) for (k,v) in pairs(attrs)), collect(children))
# m(tag::String, child::String; attrs...) = Node(ELEMENT_NODE, tag, OrderedDict(k=>string(v) for (k,v) in pairs(attrs)), child)
Base.getproperty(::typeof(m), sym::Symbol) = (f(args...; kw...) = m(string(sym), args...; kw...))

function check(o::Node)
    if type == DOCUMENT_NODE
        isnothing(o.tag) || error("A DOCUMENT_NODE should not have a tag.")
        isnothing(o.attributes) || error("A DOCUMENT_NODE should not have attributes.")
        o.children isa Vector{Node} || error("DOCUMENT_NODE children should be Vector{Node}.")
    elseif type == DTD_NODE
        isnothing(o.tag) || error("A DTD_NODE should not have a tag.")
        isnothing(o.children) || error("A DTD_NODE should not have children.")
    elseif type == DECLARATION_NODE
        isnothing(o.children) || error("A DECLARATION_NODE should not have children.")
    elseif type == COMMENT_NODE
        isnothing(o.tag) || error("A COMMENT_NODE should not have a tag.")
        isnothing(o.attributes) || error("A COMMENT_NODE should not have attributes.")
        o.children isa String || error("A COMMENT_NODE's child should be a String.")
    elseif type == CDATA_NODE
        isnothing(o.tag) || error("A CDATA_NODE should not have a tag.")
        isnothing(o.attributes) || error("A CDATA_NODE should not have attributes.")
        o.children isa String || error("A CDATA_NODE's child should be a String.")
    end
end

attr_string(o::Node) = join(" $k=$(repr(v))" for (k,v) in o.attributes)

#-----------------------------------------------------------------------------# show
function showxml(io::IO, o::Node; depth=0)
    p(args...) = printstyled(io, args...; color=depth + 1)
    if o.type == DOCUMENT_NODE
        for (i,child) in enumerate(o.children)
            showxml(io, child; depth=0)
            i != length(o.children) && println(io)
        end
    elseif o.type == DTD_NODE
        p(INDENT^depth, "<!doctype ", o.children, '>')
    elseif o.type == DECLARATION_NODE
        p(INDENT^depth, "<?", o.tag, attr_string(o), "?>")
    elseif o.type == COMMENT_NODE
        p(INDENT^depth, "<!-- ", o.children, " -->")
    elseif o.type == CDATA_NODE
        p(INDENT^depth, "<![CDATA[", o.children, "]]>")
    elseif o.type == ELEMENT_NODE
        p(INDENT^depth, '<', o.tag, attr_string(o))
        if isnothing(o.children)
            p(" />")
        else
            if length(o.children) == 1 && o.children[1] isa String
                p('>')
                showxml(io, o.children[1])
                p("</", o.tag, '>')
            else
                p('>', '\n')
                for child in o.children
                    showxml(io, child, depth=depth+1)
                    println(io)
                end
                p(INDENT^depth, "</", o.tag, '>')
            end
        end
    end
end


Base.getindex(o::Node, i::Integer) = o.children[i]
Base.setindex!(o::Node, val, i::Integer) = setindex!(o.children, val, i)
Base.lastindex(o::Node) = lastindex(o.children)

#-----------------------------------------------------------------------------# From XMLTokenIterator
function Node(itr::XMLTokenIterator)
    doc = Node(DOCUMENT_NODE, nothing, nothing, [])
    add_children!(doc, itr, "END_OF_FILE")
    return doc
end


readnode(file::String) = open(io -> Node(XMLTokenIterator(io)), file, "r")

function add_children!(e::Node, o::XMLTokenIterator, until::String)
    s = ""
    c = e.children
    while s != until
        next = iterate(o, -1)  # if state == 0, io will get reset to original position
        isnothing(next) && break
        T, s = next[1]
        if T == COMMENTTOKEN
            push!(c, comment(strip(replace(s, "<!--" => "", "-->" => ""))))
        elseif T == CDATATOKEN
            push!(c, cdata(replace(s, "<![CDATA[" => "", "]]>" => "")))
        elseif T == ELEMENTSELFCLOSEDTOKEN
            push!(c, Node(ELEMENT_NODE, get_tag(s), get_attributes(s), nothing))
        elseif T == ELEMENTTOKEN
            child = Node(ELEMENT_NODE, get_tag(s), get_attributes(s), [])
            add_children!(child, o, "</$(child.tag)>")
            push!(c, child)
        elseif T == TEXTTOKEN
            push!(c, unescape(s))
        elseif T == DTDTOKEN
            push!(c, dtd(replace(s, "<!doctype " => "", "<!DOCTYPE " => "", '>' => "")))
        elseif T == DECLARATIONTOKEN
            push!(c, Node(DECLARATION_NODE, get_tag(s), get_attributes(s), nothing))
        end
    end
end
