using XMLParser
using Test

@testset "XMLParser.jl" begin
    xml = XMLParser.parsefile(joinpath(@__DIR__, "example.kml"))
end
