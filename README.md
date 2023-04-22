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

doc = read(filename, Node)

children(doc)
# 2-Element Vector{Node}:
#  Node Declaration <?xml version="1.0"?>
#  Node Element <catalog> (12 children)

doc[end]  # The root node
# Node Element <catalog> (12 children)

doc[end][2]  # Second child of root
# Node Element <book id="bk102"> (6 children)
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

- **XML** defines `(::NodeType)(args...; kw...)` for more convenient syntax in creating `Node`s, e.g.:

```julia
CData(value)
Comment(value)
Declaration(; attributes...)
Document(children...)
DTD(; attributes...)
Element(tag, children...; attributes...)
ProcessingInstruction(; attributes...)
Text(value)
```

### `XML.LazyNode`

A lazy data structure that just keeps track of the position in the raw data (`Vector{UInt8}`) to read from.

- Iteration in depth first search (DFS) order.  This is the natural order in which you would visit XML nodes by reading an XML document from top to bottom.

```julia
doc = read(filename, LazyNode)

foreach(println, doc)
# LazyNode Declaration <?xml version="1.0"?>
# LazyNode Element <catalog>
# LazyNode Element <book id="bk101">
# LazyNode Element <author>
# LazyNode Text "Gambardella, Matthew"
# LazyNode Element <title>
# ⋮
```


## Reading

```julia
# Reading from file:
read(filename, Node)
read(filename, LazyNode)

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
    - The most fair comparison is between `XML.Node` and `XMLDict.xml_dict`.
- See the `benchmarks/suite.jl` file.

```
8×2 DataFrame
 Row │ name                    bench
     │ String                  Trial
─────┼───────────────────────────────────────────
   1 │ XML.Raw                 Trial(9.958 μs)
   2 │ XML.LazyNode            Trial(10.000 μs)
   3 │ collect(XML.LazyNode)   Trial(56.973 ms)
   4 │ XML.Node                Trial(990.248 ms)
   5 │ EzXML.readxml           Trial(158.977 ms)
   6 │ XMLDict.xml_dict        Trial(1.278 s)
   7 │ XML.LazyNode iteration  Trial(58.164 ms)
   8 │ EzXML.StreamReader      Trial(138.631 ms)
   ```
