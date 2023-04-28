#-----------------------------------------------------------------------------# position_after
function position_after(needle::Vector{UInt8}, haystack::Vector{UInt8}, i)
    x = findnext(needle, haystack, i)
    isnothing(x) ? nothing : x[end] + 1
end

position_after(needle::String, haystack::Vector{UInt8}, i) = position_after(Vector{UInt8}(needle), haystack, i)




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
    i = position_after("<!ELEMENT", data, 1)
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
        i = position_after("<!ELEMENT", data, i)
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
    i = position_after("<!ATTLIST", data, 1)
    out = DeclaredAttribute[]
    while !isnothing(i)
        element_name, i = get_name(data, i)
        attribute_name, i = get_name(data, i)
        i = findnext(!isspace, data, i)
        attribute_type = if data[i] == UInt('(')
            j = findnext(==(UInt8(')')), data, i)
            String(data[i:j])
            i = j + 1
        else
            nm, i = get_name(data, i)
            nm
        end
        i = findnext(!isspace, data, i)
        is_hash = data[i] == UInt8('#')
        val, i = get_name(data, i)
        attribute_value = is_hash ? '#' * val : val
        push!(out, DeclaredAttribute(element_name, attribute_name, attribute_type, attribute_value))
        i = position_after("<!ATTLIST", data, i)
    end
    return out
end

#-----------------------------------------------------------------------------# DeclaredEntity
struct DeclaredEntity
    name::String
    external::Bool
    value::String
end
function Base.show(io::IO, o::DeclaredEntity)
    print(io, "<!ENTITY ", o.name, " ", o.external ? "SYSTEM" : "", repr(o.value), ">")
end

function get_declared_entities(data)
    i = position_after("<!ENTITY", data, 1)
    out = DeclaredEntity[]
    while !isnothing(i)
        name, i = get_name(data, i)
        value, i = get_name(data, i)
        external = value == "SYSTEM"
        if external
            value, i = get_name(data, i)
        end
        push!(out, DeclaredEntity(name, external, value))
        i = position_after("<!ENTITY", data, i)
    end
    return out
end

#-----------------------------------------------------------------------------# DTDBody
struct DTDBody
    root::String
    elements::Vector{DeclaredElement}
    attributes::Vector{DeclaredAttribute}
    entities::Vector{DeclaredEntity}
end

function Base.show(io::IO, o::DTDBody)
    printstyled(io, "DTDBody(root=\"", o.root, "\")\n", color=:light_cyan)
    printstyled(io, "   DeclaredElements (", length(o.elements), ")\n", color=:light_green)
    foreach(x -> println(io, "        ", x), o.elements)
    printstyled(io, "    DeclaredAttributes (", length(o.attributes), ")\n", color=:light_green)
    foreach(x -> println(io, "        ", x), o.attributes)
    printstyled(io, "    DeclaredEntities (", length(o.entities), ")\n", color=:light_green)
    foreach(x -> println(io, "        ", x), o.entities)
end



function DTDBody(data::Vector{UInt8})
    i = position_after("<!DOCTYPE", data, 1)
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
