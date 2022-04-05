<h1 align="center">XMLParser</h1>

<br><br>

## Usage

```julia
using XMLParser

doc = XMLParser.parsefile("file.xml")
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
    - `XMLParser.Comment`
    - `XMLParser.CData`
    - `XMLParser.Element`
