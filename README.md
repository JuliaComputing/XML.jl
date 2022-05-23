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

### Types

```julia
# <!DOCTYPE $text>
struct DTD <: AbstractXMLNode
    text::String
end

# <?xml $attributes ?>
mutable struct Declaration <: AbstractXMLNode
    tag::String
    attributes::OrderedDict{Symbol, String}
end

# <![CDATA[$text]]>
mutable struct CData <: AbstractXMLNode
    text::String
end

# <!-- $text -->
mutable struct Comment <: AbstractXMLNode
    text::String
end

# <$tag $attributes>$children</$tag>
mutable struct Element <: AbstractXMLNode
    tag::String
    attributes::OrderedDict{Symbol, String}
    children::Vector{Union{CData, Comment, Element, String}}
end

mutable struct Document <: AbstractXMLNode
    prolog::Vector{Union{Comment, Declaration, DTD}}
    root::Element
end
```
