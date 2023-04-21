using XML: XML
using EzXML: EzXML
using XMLDict: XMLDict
using BenchmarkTools


# http://aiweb.cs.washington.edu/research/projects/xmltk/xmldata/www/repository.html#nasa
file = joinpath(@__DIR__, "nasa.xml")

#-----------------------------------------------------------------------------# Read
@info "XML.Raw" @benchmark XML.Raw($file)
@info "XML.LazyNode" @benchmark XML.LazyNode($file)
# @info "XML.Node" @benchmark Node($file)
# @info "XML.RowNode" @benchmark XML.RowNode($file)
# @info "EzXML.readxml" @benchmark EzXML.readxml($file)
# @info "XMLDict.xml_dict" @benchmark XMLDict.xml_dict(read($file, String))

# #-----------------------------------------------------------------------------# Iteration
# @info "XML.RawData iteration" @benchmark (for x in XML.RawData($file); end)
# @info "XML.RowNode iteration" @benchmark (for x in XML.RowNode($file); end)

# @info "EzXML.StreamReader" @benchmark (reader = open(EzXML.StreamReader, $file); for x in reader; end; close(reader))
