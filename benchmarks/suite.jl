using XML: XML
using EzXML: EzXML
using BenchmarkTools


file = download("http://schemas.opengis.net/kml/2.2.0/ogckml22.xsd")
filename = tempname()

#-----------------------------------------------------------------------------# read
@info "XML lazy read" @benchmark XML.RawData($file)

@info "EzXML read" @benchmark EzXML.readxml($file)
