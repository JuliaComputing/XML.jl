using XML: XML
using EzXML: EzXML
using XMLDict: XMLDict
using BenchmarkTools


file = download("http://schemas.opengis.net/kml/2.2.0/ogckml22.xsd")

#-----------------------------------------------------------------------------# Read
@info "XML.FastNode" @benchmark XML.FastNode($file)
@info "XML.Node" @benchmark Node($file)
@info "XML.RowNode" @benchmark XML.RowNode($file)
@info "EzXML.readxml" @benchmark EzXML.readxml($file)
@info "XMLDict.xml_dict" @benchmark XMLDict.xml_dict(read($file, String))

#-----------------------------------------------------------------------------# Iteration
@info "XML.RawData iteration" @benchmark (for x in XML.RawData($file); end)
@info "XML.RowNode iteration" @benchmark (for x in XML.RowNode($file); end)

@info "EzXML.StreamReader" @benchmark (reader = open(EzXML.StreamReader, $file); for x in reader; end; close(reader))
