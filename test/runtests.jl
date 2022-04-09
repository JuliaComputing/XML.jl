using XML: document
using Downloads: download
using Test

@testset "XML.jl" begin
    @testset "example.kml" begin
        doc = document(joinpath(@__DIR__, "example.kml"))
        write("test.xml", doc)
        doc2 = document("test.xml")
        @test doc == doc2
    end

    @testset "books.xml" begin
        doc = document(joinpath(@__DIR__, "books.xml"))
        write("test.xml", doc)
        doc2 = document("test.xml")
        @test doc == doc2
    end

    @testset "KML spec" begin
        doc = document(download("http://schemas.opengis.net/kml/2.2.0/ogckml22.xsd"))
        write("test.xml", doc)
        doc2 = document("test.xml")
        @test doc == doc2
    end
end
