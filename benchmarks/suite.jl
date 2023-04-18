using XML: XML
using EzXML: EzXML
using BenchmarkTools


file = download("http://schemas.opengis.net/kml/2.2.0/ogckml22.xsd")
filename = tempname()

#-----------------------------------------------------------------------------# read
@info "XML Document read" @benchmark XML.read($file, XML.Node)
@info "XML Document read" @benchmark open(io -> collect(XML.FileIterator(io)), $file, "r")
@info "EzXML read" @benchmark EzXML.readxml($file)
