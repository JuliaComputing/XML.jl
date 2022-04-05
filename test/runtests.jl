using XMLFiles
using Test

@testset "XMLFiles.jl" begin
    xml = XMLFiles.parsefile(joinpath(@__DIR__, "example.kml"))
    xml2 = XMLFiles.parsefile(joinpath(@__DIR__, "books.xml"))
end
