<h1 align="center">XMLFiles.jl</h1>

<p align="center">Read and write XML Files in 100% Julia.</p>

<br><br>

## Usage

```julia
using XMLFiles

doc = XMLFiles.parsefile("file.xml")
```

<br><br>

## Approach

1. `itr = <eachline but splits on "<">`
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
