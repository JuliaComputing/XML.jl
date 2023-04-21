using XML: XML
using EzXML: EzXML
using XMLDict: XMLDict
using BenchmarkTools


# nasa.xml was downloaded from:
# http://aiweb.cs.washington.edu/research/projects/xmltk/xmldata/www/repository.html#nasa
file = joinpath(@__DIR__, "nasa.xml")

#-----------------------------------------------------------------------------# Read
@info "XML.Raw" @benchmark XML.Raw($file)  # median: 10.083 μs (0.00% GC)
@info "XML.LazyNode" @benchmark XML.LazyNode($file)  # median: 10.250 μs (0.00% GC)
@info "collect(XML.LazyNode)" @benchmark collect(XML.LazyNode($file))  # median 102.149 ms (24.51% GC)
@info "XML.Node" @benchmark Node($file)  # median: 1.085 s (16.16% GC)
@info "EzXML.readxml" @benchmark EzXML.readxml($file)  # median: 192.345 ms
@info "XMLDict.xml_dict" @benchmark XMLDict.xml_dict(read($file, String))  # median: 1.525 s (GC 23.17%)

#-----------------------------------------------------------------------------# Iteration
@info "XML.LazyNode iteration" @benchmark (for x in XML.LazyNode($file); end)  # 67.547 ms (16.55% GC)
@info "EzXML.StreamReader" @benchmark (reader = open(EzXML.StreamReader, $file); for x in reader; end; close(reader))  # median 142.340 ms
