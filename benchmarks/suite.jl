using XML: XML
using EzXML: EzXML
using XMLDict: XMLDict
using BenchmarkTools
using DataFrames


# nasa.xml was downloaded from:
# http://aiweb.cs.washington.edu/research/projects/xmltk/xmldata/www/repository.html#nasa
file = joinpath(@__DIR__, "nasa.xml")



#-----------------------------------------------------------------------------# benchmarks
benchmarks = []

@info "XML.Raw"
push!(benchmarks, "XML.Raw" => @benchmark(read($file, XML.Raw)))

@info "XML.LazyNode"
push!(benchmarks, "XML.LazyNode" => @benchmark(read($file, LazyNode)))

@info "collect(LazyNode)"
push!(benchmarks, "collect(XML.LazyNode)" => @benchmark(collect(read($file, LazyNode))))

@info "XML.Node"
push!(benchmarks, "XML.Node" => @benchmark(read($file, Node)))

@info "EzXML"
push!(benchmarks, "EzXML.readxml" => @benchmark(EzXML.readxml($file)))

@info "XMLDict"
push!(benchmarks, "XMLDict.xml_dict" => @benchmark(XMLDict.xml_dict(read($file, String))))

@info "LazyNode iteration"
push!(benchmarks, "XML.LazyNode iteration" => @benchmark((for x in read($file, LazyNode); end)))

@info "EzXML.StreamReader iteration"
push!(benchmarks, "EzXML.StreamReader" => @benchmark((reader = open(EzXML.StreamReader, $file); for x in reader; end; close(reader))))

#-----------------------------------------------------------------------------# make DataFrame
out = DataFrame()

for (name, bench) in benchmarks
    push!(out, (; name, bench))
end

out
