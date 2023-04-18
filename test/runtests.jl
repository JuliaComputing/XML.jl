using XML
using Downloads: download
using Test
using AbstractTrees

#-----------------------------------------------------------------------------# roundtrip
@testset "read/write/read roundtrip" begin
    for file = ["books.xml", "example.kml"]
        node = Node(file)
        temp = "test.xml"
        XML.write(temp, node)
        node2 = Node(temp)
        for (a,b) in zip(AbstractTrees.Leaves(node), AbstractTrees.Leaves(node2))
            @test a == b
        end
    end
end

#-----------------------------------------------------------------------------# Tokens
@testset "Tokens" begin
    file = "books.xml"
    t = XML.Tokens(file)
    doc = collect(t)
    @test length(doc) > countlines(file)
    # Check that the first 5 lines are correct
    first_5_lines = [
        XML.TOK_DECLARATION => """<?xml version="1.0"?>""",
        XML.TOK_START_ELEMENT => "<catalog>",
        XML.TOK_START_ELEMENT => "<book id=\"bk101\">",
        XML.TOK_START_ELEMENT => "<author>",
        XML.TOK_TEXT => "Gambardella, Matthew"
    ]
    for (i, (tok, str)) in enumerate(first_5_lines)
        tokdata = doc[i]
        @test tokdata.tok == tok
        @test String(tokdata) == str
    end
    # Check that the last line is correct
    @test doc[end].tok == XML.TOK_END_ELEMENT
    @test String(doc[end]) == "</catalog>"

    @testset "next and prev" begin
        @test XML.prev(doc[1]) === nothing
        @test XML.next(doc[end]) === nothing

        next_res = [doc[1], XML.next.(doc[1:end-1])...]
        prev_res = [XML.prev.(doc[2:end])..., doc[end]]

        idx = findall(next_res .!= prev_res)

        for (a,b) in zip(next_res, prev_res)
            @test a == b
        end
    end
end



# @testset "XML.jl" begin
#     @testset "Separate structs" begin
#         @testset "example.kml" begin
#             doc = Document(joinpath(@__DIR__, "example.kml"))
#             write("test.xml", doc)
#             doc2 = Document("test.xml")
#             @test doc == doc2
#         end
#         @testset "equality" begin
#             @test XML.h("tag"; x=1, y=2) == XML.h("tag"; y=2, x=1)
#             @test XML.h("tag"; x=1, y=2) != XML.h("tag"; y=1, x=1)
#         end

#         @testset "books.xml" begin
#             doc = Document(joinpath(@__DIR__, "books.xml"))
#             write("test.xml", doc)
#             doc2 = Document("test.xml")
#             @test doc == doc2
#         end

#         @testset "KML spec" begin
#             doc = Document(download("http://schemas.opengis.net/kml/2.2.0/ogckml22.xsd"))
#             write("test.xml", doc)
#             doc2 = Document("test.xml")
#             @test doc == doc2
#         end
#     end

#     @testset "Node" begin
#         @testset "example.kml" begin
#             doc = XML.readnode(joinpath(@__DIR__, "example.kml"))
#             write("test.xml", doc)
#             doc2 = XML.readnode("test.xml")
#             @test doc == doc2
#         end

#         @testset "books.xml" begin
#             doc = XML.readnode(joinpath(@__DIR__, "books.xml"))
#             write("test.xml", doc)
#             doc2 = XML.readnode("test.xml")
#             @test doc == doc2
#         end

#         @testset "KML spec" begin
#             doc = XML.readnode(download("http://schemas.opengis.net/kml/2.2.0/ogckml22.xsd"))
#             write("test.xml", doc)
#             doc2 = XML.readnode("test.xml")
#             @test doc == doc2
#         end
#     end

#     # cleanup
    rm("test.xml", force=true)
# end
