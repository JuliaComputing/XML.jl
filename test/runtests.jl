using XML
using Downloads: download
using Test

@testset "XML.jl" begin
    @testset "Separate structs" begin
        @testset "example.kml" begin
            doc = Document(joinpath(@__DIR__, "example.kml"))
            write("test.xml", doc)
            doc2 = Document("test.xml")
            @test doc == doc2
        end

        @testset "books.xml" begin
            doc = Document(joinpath(@__DIR__, "books.xml"))
            write("test.xml", doc)
            doc2 = Document("test.xml")
            @test doc == doc2
        end

        @testset "KML spec" begin
            doc = Document(download("http://schemas.opengis.net/kml/2.2.0/ogckml22.xsd"))
            write("test.xml", doc)
            doc2 = Document("test.xml")
            @test doc == doc2
        end
    end

    @testset "Node" begin
        @testset "example.kml" begin
            doc = XML.readnode(joinpath(@__DIR__, "example.kml"))
            write("test.xml", doc)
            doc2 = XML.readnode("test.xml")
            @test doc == doc2
        end

        @testset "books.xml" begin
            doc = XML.readnode(joinpath(@__DIR__, "books.xml"))
            write("test.xml", doc)
            doc2 = XML.readnode("test.xml")
            @test doc == doc2
        end

        @testset "KML spec" begin
            doc = XML.readnode(download("http://schemas.opengis.net/kml/2.2.0/ogckml22.xsd"))
            write("test.xml", doc)
            doc2 = XML.readnode("test.xml")
            @test doc == doc2
        end
    end

    # cleanup
    rm("test.xml", force=true)
end
