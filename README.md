<h1 align="center">XML.jl</h1>

<p align="center">Read and write XML in pure Julia.</p>

<br><br>

## Quickstart

```julia
using XML

doc = XML.Document("file.xml")

# Use `getindex`/`setindex! to get/set child elements

doc[1:end-1]    # The doc's prolog
doc[end]        # The doc's root.  Same as `XML.root(doc)`


# Use `getproperty`/`setproperty!` to get/set element attributes
doc[end].some_root_element_attribute

write("newfile.xml", doc)
```

## Internals

XML.jl puts all XML content into the following struct:

```julia
# The kind of Node
@enum(NodeType,
    DOCUMENT,           # children[1:end-1] == prolog, children[end] == root,
    DOCTYPE,            # <!DOCTYPE content >
    DECLARATION,        # <?xml attributes>
    COMMENT,            # <!-- content -->
    CDATA,              # <![CDATA[content]]>
    ELEMENT,            # <tag attributes>
    ELEMENTSELFCLOSED,  # <tag attributes/>
    TEXT                # I'm something that is between a tag's close '>' and the next tag's '<'
)

Base.@kwdef mutable struct Node
    nodetype::NodeType  # see above
    tag::String = ""    # a node's tag, used for DECLARATION, ELEMENT, and ELEMENTSELFCLOSED
    attributes::OrderedDict{String, String} = OrderedDict{String,String}() # a node's attributes e.g. `id="some id"`
    children::Vector{Node} = Node[]  # child elements of ELEMENT
    content::String = ""  # used for DOCTYPE, COMMENT, CDATA, and TEXT
end
```
