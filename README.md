<h1 align="center">XML.jl</h1>

<p align="center">Read and write XML in pure Julia.</p>

<br><br>

## Quickstart

```julia
using XML

doc = XML.Document(joinpath(dirname(pathof(XML)), "..", "test", "books.xml"))

doc.prolog
 # <?xml version="1.0"?>

doc.root
# <catalog> (12 children)

# Use getindex/setindex! to get/set an Element's children
doc.root[1]
# <book id="bk101"> (6 children)

doc.root[1][1]
# <author> (1 child)

# use getproperty/setproperty! to get/set an Element's attributes

doc.root.id = "A new attribute called `id`"

write("newfile.xml", doc)
```

## Internals

### Types

```julia
# Document Type Definition (https://www.w3schools.com/xml/xml_dtd.asp)
# XML: <!DOCTYPE $text>
struct DTD <: AbstractXMLNode
    text::String
end

# (https://www.tutorialspoint.com/xml/xml_declaration.htm)
# XML: <?xml $attributes ?>
mutable struct Declaration <: AbstractXMLNode
    tag::String
    attributes::OrderedDict{Symbol, String}
end

# (https://www.tutorialspoint.com/xml/xml_cdata_sections.htm)
# XML: <![CDATA[$text]]>
mutable struct CData <: AbstractXMLNode
    text::String
end

# XML: <!-- $text -->
mutable struct Comment <: AbstractXMLNode
    text::String
end

# (https://www.w3schools.com/xml/xml_elements.asp)
# XML: <$tag $attributes>$children</$tag>
mutable struct Element <: AbstractXMLNode
    tag::String
    attributes::OrderedDict{Symbol, String}
    children::Vector{Union{CData, Comment, Element, String}}
end

# XML documents must have a root node.  Everything comes before the root is the "prolog"
mutable struct Document <: AbstractXMLNode
    prolog::Vector{Union{Comment, Declaration, DTD}}
    root::Element
end
```
