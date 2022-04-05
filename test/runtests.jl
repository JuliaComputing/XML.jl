using XMLFiles
using Test

@testset "XMLFiles.jl" begin
    @testset "example.kml" begin
        xml = XMLFiles.parsefile(joinpath(@__DIR__, "example.kml"))
        write("test.xml", xml)
        xml2 = XMLFiles.parsefile("test.xml")
        @test xml == xml2
    end

    @testset "books.xml" begin
        xml = XMLFiles.parsefile(joinpath(@__DIR__, "books.xml"))
        write("test.xml", xml)
        xml2 = XMLFiles.parsefile("test.xml")
        @test xml == xml2
    end
end
