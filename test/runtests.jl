using XML
using Downloads: download
using Test
using AbstractTrees



#-----------------------------------------------------------------------------# Tokens
@testset "RawData" begin
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
        @test XML.prev(doc[1]) === nothing
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
end


#-----------------------------------------------------------------------------# roundtrip
# @testset "read/write/read roundtrip" begin
#     for file = ["books.xml", "example.kml"]
#         node = Node(file)
#         temp = "test.xml"
#         XML.write(temp, node)
#         node2 = Node(temp)
#         for (a,b) in zip(AbstractTrees.Leaves(node), AbstractTrees.Leaves(node2))
#             @test a == b
#         end
#     end
# end



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
