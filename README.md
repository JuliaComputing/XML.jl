# XMLParser

## Usage

```julia
using XMLParser

s = read("file.xml", String)

doc = XMLParser.parse(s)
```

## Approach

1. `itr = Iterators.split(input_string, '<')
2. To satisfy the XML spec, each element of this iterator must begin with one of:
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
