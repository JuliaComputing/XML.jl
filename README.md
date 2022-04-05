<h1 align="center">XMLFiles.jl</h1>

<p align="center">Read and write XML Files in 100% Julia.</p>

<br><br>

## Quickstart

```julia
using XMLFiles

doc = XMLFiles.parsefile("file.xml")

# `doc` has two fields:
doc.prolog
doc.root

# The root `XMLFiles.Element` has fields:
doc.root.tag        # String tag
doc.root.attrs      # OrderedDict{String,String} of attributes
doc.root.children   # Vector{Any} of children


write("newfile.xml", doc)
```

## Structs

XMLFiles.jl implements only a few simple structs.  See their help e.g. `?Comment` for more info.

```julia
mutable struct Comment
    data::String
end

mutable struct CData
    data::String
end

mutable struct Element
    tag::String
    attrs::OrderedDict{String,String}
    children::Vector
end

mutable struct Document
    prolog::Vector{Element}
    root::Element
end
```


<br><br>

## Approach

1. `itr` = `eachline` but splits on `'<'`
2. To satisfy the XML spec, each element of `itr` must begin with one of:
    - `?tag` (prolog only)
    - `!tag` (prolog only)
    - `!--` (comment)
    - `![CDATA` (like a comment, but different)
    - `tag` (opening tag)
    - `/tag>` (closing tag)
3.  Once the above is identified, it's fairly straightforward to create one of:
    - `XMLFiles.Comment`
    - `XMLFiles.CData`
    - `XMLFiles.Element`
