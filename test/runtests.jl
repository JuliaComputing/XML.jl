using XML
using Downloads: download
using Test

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

#-----------------------------------------------------------------------------# RawData
@testset "RawData tag/attributes/value" begin
    examples = [
        (xml = "<!DOCTYPE html>",
            nodetype = XML.DTD,
            tag=nothing,
            attributes=nothing,
            value="html"),

        (xml = "<?xml version=\"1.0\" key=\"value\"?>",
            nodetype = XML.DECLARATION,
            tag=nothing,
            attributes=Dict("version" => "1.0", "key" => "value"),
            value=nothing),

        (xml = "<tag _id=\"1\", x=\"abc\" />",
            nodetype = XML.ELEMENT,
            tag="tag",
            attributes=Dict("_id" => "1", "x" => "abc"),
            value=nothing),
        (xml = "<!-- comment -->",
            nodetype = XML.COMMENT,
            tag=nothing,
            attributes=nothing,
            value=" comment "),

        (xml = "<![CDATA[cdata test]]>",
            nodetype = XML.CDATA,
            tag=nothing,
            attributes=nothing,
            value="cdata test"),
    ]
    for x in examples
        # @info "Testing: $(x.xml)"
        data = XML.next(XML.parse(x.xml, XML.RawData))
        @test XML.nodetype(data) == x.nodetype
        @test XML.tag(data) == x.tag
        @test XML.attributes(data) == x.attributes
        @test XML.value(data) == x.value
    end
end

@testset "RawData with books.xml" begin
    file = "books.xml"
    data = XML.RawData(file)
    doc = collect(data)
    @test length(doc) > countlines(file)
    # Check that the first 5 lines are correct
    first_5_lines = [
        XML.RAW_DECLARATION => """<?xml version="1.0"?>""",
        XML.RAW_ELEMENT_OPEN => "<catalog>",
        XML.RAW_ELEMENT_OPEN => "<book id=\"bk101\">",
        XML.RAW_ELEMENT_OPEN => "<author>",
        XML.RAW_TEXT => "Gambardella, Matthew"
    ]
    for (i, (typ, str)) in enumerate(first_5_lines)
        dt = doc[i]
        @test dt.type == typ
        @test String(dt) == str
    end
    # Check that the last line is correct
    @test doc[end].type == XML.RAW_ELEMENT_CLOSE
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
        node = Node(path)
        temp = tempname() * ".xml"
        XML.write(temp, node; indent = " ")
        node2 = Node(temp)
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
using XML.NodeConstructors

@testset "Node writing" begin
    doc = document(
        dtd("root_tag"),
        declaration(version=1.0),
        comment("comment"),
        processing_instruction("xml-stylesheet", href="mystyle.css", type="text/css"),
        element("root_tag", cdata("cdata"), text("text"))
    )
    @test map(nodetype, children(doc)) == [
        XML.DTD,
        XML.DECLARATION,
        XML.COMMENT,
        XML.PROCESSING_INSTRUCTION,
        XML.ELEMENT
    ]
    @test length(children(doc[end])) == 2
    @test nodetype(doc[end][1]) == XML.CDATA
    @test nodetype(doc[end][2]) == XML.TEXT
    @test value(doc[end][1]) == "cdata"
    @test value(doc[end][2]) == "text"
end
