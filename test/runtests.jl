using XML
using XML: Document, Element, Declaration, Comment, CData, DTD, ProcessingInstruction, Text, escape, unescape
using Downloads: download
using Test
import AbstractTrees

AbstractTrees.children(x::Node) = children(x)

#-----------------------------------------------------------------------------# files
xml_spec = download("http://www.w3.org/2001/xml.xsd")
kml_spec = download("http://schemas.opengis.net/kml/2.2.0/ogckml22.xsd")
books = "books.xml"
example_kml = "example.kml"

all_files = [
    "XML Spec" => xml_spec,
    "KML Spec" => kml_spec,
    "books.xml" => books,
    "example.kml" => example_kml
]

#-----------------------------------------------------------------------------# utils
@testset "utils" begin
    s = "This > string < has & some \" special ' characters"
    @test escape(s) == "This &gt; string &lt; has &amp; some &quot; special &apos; characters"
    @test escape(escape(s)) == escape(s)
    @test s == unescape(escape(s))
    @test s == unescape(unescape(escape(s)))
end

#-----------------------------------------------------------------------------# Raw
@testset "Raw tag/attributes/value" begin
    examples = [
        (xml = "<!DOCTYPE html>",
            nodetype = DTD,
            tag=nothing,
            attributes=nothing,
            value="html"),

        (xml = "<?xml version=\"1.0\" key=\"value\"?>",
            nodetype = Declaration,
            tag=nothing,
            attributes=Dict("version" => "1.0", "key" => "value"),
            value=nothing),

        (xml = "<tag _id=\"1\", x=\"abc\" />",
            nodetype = Element,
            tag="tag",
            attributes=Dict("_id" => "1", "x" => "abc"),
            value=nothing),
        (xml = "<!-- comment -->",
            nodetype = Comment,
            tag=nothing,
            attributes=nothing,
            value=" comment "),

        (xml = "<![CData[cdata test]]>",
            nodetype = CData,
            tag=nothing,
            attributes=nothing,
            value="cdata test"),
    ]
    for x in examples
        # @info "Testing: $(x.xml)"
        data = XML.next(XML.parse(x.xml, XML.Raw))
        @test XML.nodetype(data) == x.nodetype
        @test XML.tag(data) == x.tag
        @test XML.attributes(data) == x.attributes
        @test XML.value(data) == x.value
    end
end

@testset "Raw with books.xml" begin
    file = "books.xml"
    data = read(file, XML.Raw)
    doc = collect(data)
    @test length(doc) > countlines(file)
    # Check that the first 5 lines are correct
    first_5_lines = [
        XML.RawDeclaration => """<?xml version="1.0"?>""",
        XML.RawElementOpen => "<catalog>",
        XML.RawElementOpen => "<book id=\"bk101\">",
        XML.RawElementOpen => "<author>",
        XML.RawText => "Gambardella, Matthew"
    ]
    for (i, (typ, str)) in enumerate(first_5_lines)
        dt = doc[i]
        @test dt.type == typ
        @test String(dt) == str
    end
    # Check that the last line is correct
    @test doc[end].type == XML.RawElementClose
    @test String(doc[end]) == "</catalog>"

    @testset "next and prev" begin
        @test XML.prev(doc[1]) === data
        @test prev(data) === nothing
        @test XML.next(doc[end]) === nothing

        n = length(doc)
        next_res = [doc[1]]
        foreach(_ -> push!(next_res, XML.next(next_res[end])), 1:n-1)

        prev_res = [doc[end]]
        foreach(_ -> pushfirst!(prev_res, XML.prev(prev_res[1])), 1:n-1)

        idx = findall(next_res .!= prev_res)

        for (a,b) in zip(next_res, prev_res)
            @test a == b
        end
    end

    @testset "tag/attributes/value" begin
        x = doc[1]  # <?xml version="1.0"?>
        @test XML.tag(x) === nothing
        @test XML.attributes(x) == Dict("version" => "1.0")
        @test XML.value(x) === nothing

        x = XML.next(x)  # <catalog>
        @test XML.tag(x) == "catalog"
        @test XML.attributes(x) === nothing
        @test XML.value(x) === nothing

        x = XML.next(x)  # <book id="bk101">
        @test XML.tag(x) == "book"
        @test XML.attributes(x) == Dict("id" => "bk101")
        @test XML.value(x) === nothing

        x = XML.next(x)  # <author>
        @test XML.tag(x) == "author"
        @test XML.attributes(x) === nothing
        @test XML.value(x) === nothing

        x = XML.next(x)  # Gambardella, Matthew
        @test XML.tag(x) === nothing
        @test XML.attributes(x) === nothing
        @test XML.value(x) == "Gambardella, Matthew"
    end
end

#-----------------------------------------------------------------------------# roundtrip
@testset "read/write/read roundtrip" begin
    for (name, path) = all_files
        # @info "read/write/read roundtrip" name
        node = read(path, Node)
        temp = tempname() * ".xml"
        XML.write(temp, node)
        node2 = read(temp, Node)
        @test node == node2

        # For debugging:
        # for (a,b) in zip(AbstractTrees.Leaves(node), AbstractTrees.Leaves(node2))
        #     if a != b
        #         @info a
        #         @info b
        #         error()
        #     end
        # end
    end
end

#-----------------------------------------------------------------------------# Node writing
@testset "Node writing" begin
    doc = Document(
        DTD("root_tag"),
        Declaration(version=1.0),
        Comment("comment"),
        ProcessingInstruction("xml-stylesheet", href="mystyle.css", type="text/css"),
        Element("root_tag", CData("cdata"), Text("text"))
    )
    @test map(nodetype, children(doc)) == [DTD,Declaration,Comment,ProcessingInstruction,Element]
    @test length(children(doc[end])) == 2
    @test nodetype(doc[end][1]) == XML.CData
    @test nodetype(doc[end][2]) == XML.Text
    @test value(doc[end][1]) == "cdata"
    @test value(doc[end][2]) == "text"

    #set/get index for attributes
    o = doc[end]
    o["id"] = 1
    @test o["id"] == "1"
end

#-----------------------------------------------------------------------------# Issues
@testset "Issues" begin
    #12
    s = """
    <?xml version="1.0" encoding="UTF-8"?>

    <!DOCTYPE note [
    <!ENTITY nbsp "&#xA0;">
    <!ENTITY writer "Writer: Donald Duck.">
    <!ENTITY copyright "Copyright: W3Schools.">
    ]>

    <note>
    <to>Tove</to>
    <from>Jani</from>
    <heading>Reminder</heading>
    <body>Don't forget me this weekend!</body>
    <footer>&writer;&nbsp;&copyright;</footer>
    </note>
    """

    doc = parse(s, Node)
    @test value(doc[2]) == """note [
        <!ENTITY nbsp "&#xA0;">
        <!ENTITY writer "Writer: Donald Duck.">
        <!ENTITY copyright "Copyright: W3Schools.">
        ]"""
end
