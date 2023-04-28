[![CI](https://github.com/JuliaComputing/XML.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/JuliaComputing/XML.jl/actions/workflows/CI.yml)

<h1 align="center">XML.jl</h1>

<p align="center">Read and write XML in pure Julia.</p>

<br><br>

# Introduction

This package offers fast data structures for reading and writing XML files with a consistent interface:

<br>

### `Node`/`LazyNode` Interface:

```
nodetype(node)      →   XML.NodeType (an enum type)
tag(node)           →   String or Nothing
attributes(node)    →   Dict{String, String} or Nothing
value(node)         →   String or Nothing
children(node)      →   Vector{typeof(node)}
is_simple(node)     →   Bool (whether node is simple .e.g. <tag>item</tag>)
simplevalue(node)   →   e.g. "item" from <tag>item</tag>)
```

<br>

### Extended Interface for `LazyNode`

```
depth(node)         →   Int
next(node)          →   typeof(node)
prev(node)          →   typeof(node)
parent(node)        →   typeof(node)
```

<br><br>

# Quickstart

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

<br><br>

# Data Structures that Represent XML Nodes

## Preliminary: `NodeType`

- Each item in an XML DOM is classified by its `NodeType`.
- Every `XML.jl` struct defines a `nodetype(x)` method that returns its `NodeType`.

| NodeType | XML Representation | `Node` Constructor |
|----------|--------------------|------------------|
| `Document` | An entire document | `Document(children...)`
| `DTD` | `<!DOCTYPE ...>` | `DTD(...) `
| `Declaration` | `<?xml attributes... ?>` | `Declaration(; attrs...)`
| `ProcessingInstruction` | `<?tag attributes... ?>` | `ProcessingInstruction(tag; attrs...)`
| `Comment` | `<!-- text -->` | `Comment(text)`
| `CData` | `<![CData[text]]>` | `CData(text)`
| `Element` | `<tag attributes... > children... </NAME>` | `Element(tag, children...; attrs...)`
| `Text` | the `text` part of `<tag>text</tag>` | `Text(text)`

<br>

## `Node`: Probably What You're Looking For

- `read`-ing a `Node` loads the entire XML DOM in memory.
- **This is what you would use to build an XML document programmatically.**
- See the table above for convenience constructors.
- `Node`s have some additional methods that aid in construction/mutation:

```julia
# Add a child:
push!(parent::Node, child::Node)

# Replace a child:
parent[2] = child

# Add/change an attribute:
node["key"] = value

node["key"]
```

<br>

## `XML.LazyNode`: For Fast Iteration through an XML File

A lazy data structure that just keeps track of the position in the raw data (`Vector{UInt8}`) to read from.

- You can iterate over a `LazyNode` to "read" through an XML file:

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

<br><br>

# Reading

```julia
# Reading from file:
read(filename, Node)
read(filename, LazyNode)

# Parsing from string:
parse(Node, str)
parse(LazyNode, str)

```

<br><br>

# Writing

```julia
XML.write(filename::String, node)  # write to file

XML.write(io::IO, node)  # write to stream

XML.write(node)  # String
```


<br><br>

# Performance

- XML.jl performs comparatively to [EzXML.jl](https://github.com/JuliaIO/EzXML.jl), which wraps the C library [libxml2](https://gitlab.gnome.org/GNOME/libxml2/-/wikis/home).
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

### Writing an XML File

```
         Write: XML  ■■■■■■■■■■■■■■■■■■■■■■ 244.261
       Write: EzXML  ■■■■■■■■■■ 106.953
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

<br>
<br>

# Possible Gotchas

- XML.jl doesn't automatically escape special characters (`<`, `>`, `&`, `"`, and `'` ) for you.  However, we provide utility functions for doing the conversions back and forth:
  - `XML.escape(::String)` and `XML.unescape(::String)`
  - `XML.escape!(::Node)` and `XML.unescape!(::Node)`.
