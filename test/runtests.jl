using XML
using XML: Document, Element, Declaration, Comment, CData, DTD, ProcessingInstruction, Text, escape, unescape, OrderedDict, h
using Downloads: download
using Test
import AbstractTrees

AbstractTrees.children(x::Node) = children(x)

#-----------------------------------------------------------------------------# files
xml_xsd = joinpath("data", "xml.xsd")
kml_xsd = joinpath("data", "kml.xsd")
books_xml = joinpath("data", "books.xml")
example_kml = joinpath("data", "example.kml")
simple_dtd = joinpath("data", "simple_dtd.xml")

all_files = [xml_xsd, kml_xsd, books_xml, example_kml, simple_dtd]

#-----------------------------------------------------------------------------# h
@testset "h function" begin
    @test h.tag == XML.Element("tag")
    @test h.tag(id="id") == XML.Element("tag"; id="id")
    @test h.tag(1, 2, a="a", b="b") == XML.Element("tag", 1, 2; a="a", b="b")
end

#-----------------------------------------------------------------------------# escaping/unescaping
@testset "escaping/unescaping" begin
    s = "This > string < has & some \" special ' characters"
    @test escape(s) == "This &gt; string &lt; has &amp; some &quot; special &apos; characters"
    @test escape(escape(s)) == escape(s)
    @test s == unescape(escape(s))
    @test s == unescape(unescape(escape(s)))

    n = Element("tag", Text(s))
    @test XML.simple_value(n) == s

    XML.escape!(n)
    @test XML.simple_value(n) == escape(s)

    XML.unescape!(n)
    @test XML.simple_value(n) == s
end

#-----------------------------------------------------------------------------# DTD
# @testset "DTDBody and friends" begin
#     s = read(simple_dtd, String)
#     data = read(simple_dtd)

#     dtd = XML.DTDBody(data)
#     dtd2 = parse(s, XML.DTDBody)

#     @test length(dtd.elements) == length(dtd2.elements) == 0
#     @test length(dtd.attributes) == length(dtd2.attributes) == 0
#     @test length(dtd.entities) == length(dtd2.entities) == 3

#     o = read("data/tv.dtd", XML.DTDBody)
# end

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
    data = read(books_xml, XML.Raw)
    doc = collect(data)
    @test length(doc) > countlines(books_xml)
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
        @test XML.prev(doc[1]) == data
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

    @testset "depth and parent" begin
        @test XML.depth(data) == 0
        @test isnothing(XML.parent(data))
        @test XML.depth(doc[1]) == 1
        @test XML.parent(doc[1]) == data
        @test XML.depth(doc[2]) == 1
        @test XML.depth(doc[3]) == 2
        @test XML.parent(doc[3]) == doc[2]
        @test XML.depth(doc[end]) == 1
        @test XML.parent(doc[end]) == data
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

#-----------------------------------------------------------------------------# Preserve whitespace
@testset "xml:space" begin
    @testset "Basic xml:space functionality" begin

        # Test 1: xml:space="preserve" should preserve entirely empty whitespace
        xml1 = """<root><text xml:space="preserve">   </text></root>"""
        doc1 = parse(XML.Node, xml1)
        text_content = XML.value(doc1[1][1][1])
        @test text_content == "   "

        # Test 2: xml:space="preserve" should preserve leading and trailing whitespace
        xml2 = """<root><text xml:space="preserve">  leading and trailing spaces  </text></root>"""
        doc2 = parse(XML.Node, xml2)
        text_content = XML.value(doc2[1][1][1])
        @test text_content == "  leading and trailing spaces  "
        
        # Test 3: Without xml:space, entirely empty whitespace should create a self closing node
        xml3 = """<root><text>    </text></root>"""
        doc3 = XML.parse(XML.Node, xml3)
        text_content = XML.write(doc3[1][1])
        @test text_content == "<text/>"

        # Test 4: Without xml:space, whitespace should be normalized
        xml4 = """<root><text>  gets normalized  </text></root>"""
        doc4 = XML.parse(XML.Node, xml4)
        text_content = XML.value(doc4[1][1][1])
        @test text_content == "gets normalized"
        
        # Test 5: xml:space="default" should normalize even with preserve_xml_space=true
        xml5 = """<root><text xml:space="default">  gets normalized  </text></root>"""
        doc5 = XML.parse(XML.Node, xml5)
        text_content = XML.value(doc5[1][1][1])
        @test text_content == "gets normalized"
    end
    
    @testset "xml:space inheritance" begin
        # Test 6: Children inherit parent's xml:space="preserve"
        xml6 = """<root xml:space="preserve">
            <parent>  parent text  
                <child>  child text  </child>
            </parent>
        </root>"""
        doc6 = XML.parse(XML.Node, xml6)
        # Both parent and child should preserve whitespace
        @test contains(XML.value(doc6[1][1][1]), "parent text  \n")
        @test XML.value(doc6[1][1][2][1]) == "  child text  "
        
        # Test 7: xml:space="default" overrides parent's "preserve"
        xml7 = """<root xml:space="preserve">
            <child xml:space="default">  normalized despite parent  </child>
        </root>"""
        doc7 = XML.parse(XML.Node, xml7)
        @test XML.value(doc7[1][1][1]) == "normalized despite parent"
    end
    
    @testset "Nesting scenarios" begin
        # Test 8: Multiple levels of xml:space changes
        xml8 = """<root xml:space="preserve">
            <level1>  preserved  
                <level2 xml:space="default">  normalized  
                    <level3 xml:space="preserve">  preserved again  </level3>
                </level2>
            </level1>
        </root>"""
        doc8 = XML.parse(XML.Node, xml8)
        
        # level1 should preserve (inherits from root)
        level1_text = XML.value(doc8[1][1][1])
        @test level1_text == "  preserved  \n        "
        
        # level2 should normalize (explicit xml:space="default")
        level2_text = XML.value(doc8[1][1][2][1])
        @test level2_text == "normalized"
        
        # level3 should preserve (explicit xml:space="preserve")
        level3_text = XML.value(doc8[1][1][2][2][1])
        @test level3_text == "  preserved again  "

        # Test 9: repeated multiple levels of xml:space changes
        xml9 = """<root xml:space="preserve">
            <level1>  preserved  
                <level2 xml:space="default">  normalized  
                    <level3 xml:space="preserve">  preserved again  </level3>
                </level2>
            </level1>  
            <level1b>  preserved b  
                <level2b xml:space="default">  normalized b 
                    <level3b xml:space="preserve">  preserved again b  </level3b>
                </level2b>
            </level1b>
        </root>"""
        doc9 = XML.parse(XML.Node, xml9)

        # level1b should preserve (inherits from root)
        level1b_text = XML.value(doc9[1][2][1])
        @test level1b_text == "  preserved b  \n        "
        
        # level2 should normalize (explicit xml:space="default")
        level2b_text = XML.value(doc9[1][2][2][1])
        @test level2b_text == "normalized b"
        
        # level3 should preserve (explicit xml:space="preserve")
        level3b_text = XML.value(doc9[1][2][2][2][1])
        @test level3b_text == "  preserved again b  "

    end
end

#-----------------------------------------------------------------------------# roundtrip
@testset "read/write/read roundtrip" begin
    for path in all_files
        node = read(path, Node)
        temp = tempname() * ".xml"
        XML.write(temp, node)
        node2 = read(temp, Node)
        @test node == node2

        #For debugging:
        for (a,b) in zip(AbstractTrees.Leaves(node), AbstractTrees.Leaves(node2))
            if a != b
                @info path
                @info a
                @info b
                error()
            end
        end
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
    @test isempty(keys(o))
    o["id"] = 1
    @test o["id"] == "1"
    @test keys(o) == keys(Dict("id" => "1"))
end

#-----------------------------------------------------------------------------# Issues
@testset "Issues" begin
    # https://github.com/JuliaComputing/XML.jl/issues/12: DTD content was cut short
    s = """
    <!DOCTYPE note [
    <!ENTITY nbsp "&#xA0;">
    <!ENTITY writer "Writer: Donald Duck.">
    <!ENTITY copyright "Copyright: W3Schools.">
    ]>
    """

    doc = parse(Node, s)
    @test value(only(doc)) == s[11:end-2]  # note [...]

    # https://github.com/JuliaComputing/XML.jl/issues/14 (Sorted Attributes)
    kw = NamedTuple(OrderedDict(Symbol(k) => Int(k) for k in 'a':'z'))
    xyz  = XML.Element("point"; kw...)
    @test collect(keys(attributes(xyz))) == string.(collect('a':'z'))
end
