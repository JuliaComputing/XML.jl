<h1 align="center">XML.jl</h1>

<p align="center">Read and write XML in pure Julia.</p>

<br><br>

## Introduction

This package offers fast data structures for reading and writing XML files with a consistent interface:

#### `Node`/`LazyNode` Interface:

- `nodetype(node)   →   XML.NodeType` (See `?XML.NodeType` for details).
- `tag(node)        →   String or Nothing`
- `attributes(node) →   Dict{String,String} or Nothing`
- `value(node)      →   String or Nothing`
- `children(node)   →   Vector{typeof(node)}`

#### Extended Interface for `LazyNode`

- `depth(node)      →   Int`
- `next(node)       →   typeof(node)`
- `prev(node)       →   typeof(node)`
- `parent(node)     →   typeof(node)`

## Quickstart

```julia
using XML

filename = joinpath(dirname(pathof(XML)), "..", "test", "books.xml")

doc = Node(filename)

children(doc)
# 2-element Vector{Node}:
#  Node DECLARATION <?xml version="1.0"?>
#  Node ELEMENT <catalog> (12 children)

doc[end]  # The root node
# Node ELEMENT <catalog> (12 children)

doc[end][2]  # Second child of root
# Node ELEMENT <book id="bk102"> (6 children)
```

## Node Types

### `XML.Node`

- An eager data structure that loads the entire XML DOM in memory.
- **This is what you would use to build an XML document programmatically.**
- `Node`s have some additional methods that aid in construction/mutation:

```julia
# Add a child:
push!(parent::Node, child::Node)

# Replace a child:
parent[2] = child
```

- `using XML.NodeConstructors` will give you access to convenience functions (`document`, `cdata`, `element`, etc.) for creating `Node`s.

```julia
using XML.NodeConstructors
# cdata, comment, declaration, document, dtd, element, processing_instruction, text

cdata("hello > < ' \" I have odd characters")
# Node CDATA <![CDATA[hello > < ' " I have odd characters]]>
```

### `XML.LazyNode`

A lazy data structure that just keeps track of the position in the raw data (`Vector{UInt8}`) to read from.

- Iteration in depth first search (DFS) order.  This is the natural order in which you would visit XML nodes by reading an XML document from top to bottom.

```julia
doc = LazyNode(filename)

foreach(println, doc)
# LazyNode DECLARATION <?xml version="1.0"?>
# LazyNode ELEMENT <catalog>
# LazyNode ELEMENT <book id="bk101">
# LazyNode ELEMENT <author>
# LazyNode TEXT "Gambardella, Matthew"
# LazyNode ELEMENT <title>
# ⋮
```


## Reading

```julia
# Reading from file:
Node(filename)
LazyNode(filename)

# Parsing from string:
parse(Node, str)
parse(LazyNode, str)

```

## Writing

```julia
XML.write(filename::String, node)  # write to file

XML.write(io::IO, node)  # write to stream

XML.write(node)  # String
```




## Performance

- Comparing benchmarks (fairly) between packages is hard.
    - The most fair comparison is between `XML.jl - Node Load` and `XMLDict.jl - read` in which XMLDict is 1.4x slower.
- See the `benchmarks/suite.jl` file.

| Benchmark | code | median time | median GC |
|-----------|------|-------------|-----------|
| XML.jl - Raw Data load | `XML.Raw($file)` | 10.083 μs | 0.00% |
| XMLjl - LazyNode load | `LazyNode($file)` | 10.250 μs | 0.00% |
| XML.jl - collect LazyNode | `collect(LazyNode($file))` | 102.149 ms | 24.51% GC |
| XML.jl - Node load | `Node($file)` | 1.085 s | 16.16% |
| EzXML.jl - read | `EzXML.readxml($file) | 192.345 ms | N/A |
| XMLDict.jl - read | `XMLDict.xml_dict(read($file, String))` | 1.525 s | GC 23.17%
| XML.jl LazyNode iteration | `for x in XML.LazyNode($file); end` | 67.547 ms | 16.55% GC
| EzXML.StreamReader | `r = open(EzXML.StreamReader, $file); for x in r; end; close(r))` | 142.340 ms | N/A
