<h1 align="center">XML.jl</h1>

<p align="center">Read and write XML in pure Julia.</p>

<br><br>

## Introduction

This package offers fast data structures for reading and writing XML files with a consistent interface:

#### `Node`/`LazyNode` Interface:

- `nodetype(node)   →   XML.NodeType` (an enum with one of the following values):
    - `Document`: `children...`
    - `DTD`: `<!DOCTYPE ...>`
    - `Declaration`: `<?xml attributes... ?>`
    - `ProcessingInstruction`: `<?NAME attributes... ?>`
    - `Comment`: `<!-- ... -->`
    - `CData`: `<![CData[...]]>`
    - `Element`: `<NAME attributes... > children... </NAME>`
    - `Text`: `text`
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

- See the `benchmarks/suite.jl` for the code to produce these results.
- The following output was generated in a Julia session with the following `versioninfo`:

```
julia> versioninfo()
Julia Version 1.8.5
Commit 17cfb8e65ea (2023-01-08 06:45 UTC)
Platform Info:
  OS: macOS (arm64-apple-darwin21.5.0)
  CPU: 10 × Apple M1 Pro
  WORD_SIZE: 64
  LIBM: libopenlibm
  LLVM: libLLVM-13.0.1 (ORCJIT, apple-m1)
  Threads: 1 on 8 virtual cores
```


### Reading an XML File

```
       XML.LazyNode   0.012084
           XML.Node  ■■■■■■■■■■■■■■■■■■■■■■■■■■■ 888.367
      EzXML.readxml  ■■■■■■ 200.009
   XMLDict.xml_dict  ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■ 1350.63
```

### Lazily Iterating over Each Node
```
           LazyNode  ■■■■■■■■■■■■■■■■ 55.1
 EzXML.StreamReader  ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■ 142.515
```

### Collecting All Names/Tags in an XML File
```
       XML.LazyNode  ■■■■■■■■■■■■■■■■■■■■■■■■■■ 152.298
 EzXML.StreamReader  ■■■■■■■■■■■■■■■■■■■■■■■■■■■■ 165.21
      EzXML.readxml  ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■ 239.197
```
