#-----------------------------------------------------------------------------# DeclaredElement
struct DeclaredElement
    name::String
    content::String  # "ANY", "EMPTY", or "(children...)"
    function DeclaredElement(name, content)
        content in ("ANY", "EMPTY") || (content[1] == '('  && content[end] == ')') ||
            error("DeclaredElement `content` must be 'ANY', 'EMPTY', or '(children...)'.  Got $content.")
        new(name, content)
    end
end
Base.show(io::IO, o::DeclaredElement) = print(io, "<!ELEMENT ", o.name, " ", o.content, ">")

function get_declared_elements(data::Vector{UInt8})
    i = findnext(Vector{UInt8}("<!ELEMENT"), data, 1)[end]
    out = DeclaredElement[]
    while !isnothing(i)
        name, i = get_name(data, i + 1)
        i = findnext(!isspace, data, i)
        if data[i] == UInt8('(')
            j = findnext(==(UInt8(')')), data, i + 1)
            content = String(data[i:j])
        else
            content, i = get_name(data, i)
        end
        push!(out, DeclaredElement(name, content))
        fn = findnext(Vector{UInt8}("<!ELEMENT"), data, i)
        i = isnothing(fn) ? nothing : fn[end]
    end
    return out
end

#-----------------------------------------------------------------------------# DeclaredAttribute
struct DeclaredAttribute
    element_name::String
    attribute_name::String
    attribute_type::String
    attribute_value::String
end
Base.show(io::IO, o::DeclaredAttribute) = print(io, "<!ATTLIST ", o.element_name, " ", o.attribute_name, " ", o.attribute_type, " ", o.attribute_value, ">")

function get_declared_attributes(data)
    []
end

#-----------------------------------------------------------------------------# DeclaredEntity
struct DeclaredEntity
    name::String
    value::String
end
Base.show(io::IO, o::DeclaredEntity) = print(io, "<!ENTITY ", o.name, " ", o.value, ">")

function get_declared_entities(data)
    []
end

#-----------------------------------------------------------------------------# DTDBody
struct DTDBody
    root::String
    elements::Vector{DeclaredElement}
    attributes::Vector{DeclaredAttribute}
    entities::Vector{DeclaredEntity}
end

function Base.show(io::IO, o::DTDBody)
    println(io, "DTDBody(root=\"", o.root)
    println(io, "  • DeclaredElements")
    foreach(x -> println(io, "    ", x), o.elements)
    println(io, "  • DeclaredAttributes")
    println(io, "  • DeclaredEntities")
end



function DTDBody(data::Vector{UInt8})
    start = "<!DOCTYPE"
    data[1:length(start)] == Vector{UInt8}(start) || error("DTD must start with `<!DOCTYPE`.")
    i = length(start) + 1
    root, i = get_name(data, i)

    i = findnext(==(UInt8('[')), data, i)
    isnothing(i) && return DTDBody(root, [], [], [])

    elements = get_declared_elements(data)
    attributes = get_declared_attributes(data)
    entities = get_declared_entities(data)
    return DTDBody(root, elements, attributes, entities)
end


Base.read(filename::String, ::Type{DTDBody}) = DTDBody(read(filename))
Base.read(io::IO, ::Type{DTDBody}) = Raw(read(io))
Base.parse(s::AbstractString, ::Type{DTDBody}) = DTDBody(Vector{UInt8}(s))
Base.parse(::Type{DTDBody}, s::AbstractString) = parse(s, DTDBody)
