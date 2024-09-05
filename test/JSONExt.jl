using JSON

@testset "XML to JSON" begin
    xml = read("data/toJSON.xml", Node)
    json = xml2json(xml)
    d = xml2dicts(xml)
    @test JSON.parse(json) == d
end
