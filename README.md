<h1 align="center">XML.jl</h1>

<p align="center">Read and write XML in pure Julia.</p>

<br><br>

## Introduction

This package offers fast data structures for reading and writing XML files with a consistent interface:

#### Interface Core:

- `nodetype(node) --> XML.NodeType` (See `?XML.NodeType` for details).
- `tag(node) --> String or Nothing`
- `attributes(node) --> OrderedDict{String,String} or Nothing`
- `value(node) --> String or Nothing`
- `children(node) --> Vector{typeof(node)}`
- `depth(node) --> Int`

#### Interface for Lazy Data Structures:
- `next(node) --> typeof(node)`
- `prev(node) --> typeof(node)`
- `parent(node) --> typeof(node)`

## Quickstart

```julia
using XML

filename = joinpath(dirname(pathof(XML)), "..", "test", "books.xml")

doc = XML.Node(filename)

children(doc)
# 2-element Vector{Node}:
#  Node DECLARATION <?xml version="1.0">
#  Node ELEMENT <catalog> (12 children)

doc[end]  # The root node
# Node ELEMENT <catalog> (12 children)

doc[end][2]  # Second child of root
# Node ELEMENT <book id="bk102"> (6 children)
```

## Data Structures

### `XML.Node`
- An eager data structure that loads the entire XML DOM in memory.
- **This is what you should use to build an XML document programmatically.**
- `Node`s have some additional methods that aid in construction/mutation:

```julia
# Add a child:
push!(parent::Node, child::Node)

# Replace a child:
parent[2] = child

# Create a new node with an edited field.  `kw...` can be one or more of:
# - nodetype::NodeType
# - tag (String or Nothing)
# - attributes (OrderedDict{String,String} or Nothing)
# - value (String or Nothing)
# - children (Vector{Node} or nothing),
# - depth::Int (this will be automatically set if not provided)
Node(node; kw...)
```

- Bring convenience functions into your namespace with `using XML.NodeConstructors`:

```julia
using XML.NodeConstructors
# cdata, comment, declaration, document, dtd, element, processing_instruction, text

cdata("hello > < ' \" I have odd characters")
# Node CDATA <![CDATA[hello > < ' " I have odd characters]]>
```

### `XML.RowNode`
- A data structure that can used as a *Tables.jl* source.  It is only lazy in how it accesses its children.


### `XML.RawData`
- A super lazy data structure that holds the reference `Vector{UInt8}` data along with position/length to read from.


## Reading

```julia
XML.RawData(filename)

RowNode(filename)

Node(filename)

# Parsing:
parse(XML.RawData, str)
parse(RowNode, str)
parse(Node, str)
```

## Writing

```julia
XML.write(filename::String, node)  # write to file

XML.write(io::IO, node)  # write to stream

XML.write(node)  # String
```

## Iteration

```julia
doc = XML.RowNode(filename)

foreach(println, doc)
# RowNode DECLARATION <?xml version="1.0">
# RowNode ELEMENT <catalog> (12 children)
# RowNode ELEMENT <book id="bk101"> (6 children)
# RowNode ELEMENT <author> (1 child)
# RowNode TEXT "Gambardella, Matthew"
# RowNode ELEMENT <title> (1 child)
# ⋮

# Use as Tables.jl source:
using DataFrames

DataFrame(doc)
```

Note that you can also iterate through `XML.RawData`.  However, *BEWARE* that this iterator
has some non-node elements (e.g. just the closing tag of an element).

```julia
data = XML.RawData(filename)

foreach(println, data)
# 1: RAW_DECLARATION (pos=1, len=20): <?xml version="1.0"?>
# 1: RAW_ELEMENT_OPEN (pos=23, len=8): <catalog>
# 2: RAW_ELEMENT_OPEN (pos=36, len=16): <book id="bk101">
# 3: RAW_ELEMENT_OPEN (pos=60, len=7): <author>
# 4: RAW_TEXT (pos=68, len=19): Gambardella, Matthew
# 3: RAW_ELEMENT_CLOSE (pos=88, len=8): </author>  <------ !!! NOT A NODE !!!
# 3: RAW_ELEMENT_OPEN (pos=104, len=6): <title>
# ⋮
```
