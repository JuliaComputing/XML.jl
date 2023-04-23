using Pkg
Pkg.activate(@__DIR__)

using XML
using EzXML: EzXML
using XMLDict: XMLDict
using BenchmarkTools
using DataFrames
using UnicodePlots
using OrderedCollections: OrderedDict


BenchmarkTools.DEFAULT_PARAMETERS.seconds = 10
BenchmarkTools.DEFAULT_PARAMETERS.samples = 20000


# nasa.xml was downloaded from:
# http://aiweb.cs.washington.edu/research/projects/xmltk/xmldata/www/repository.html#nasa
file = joinpath(@__DIR__, "nasa.xml")

df = DataFrame(kind=String[], name=String[], bench=BenchmarkTools.Trial[])

#-----------------------------------------------------------------------------# Read
kind = "Read"

# name = "XML.Raw"
# @info name
# bench = @benchmark read($file, XML.Raw)
# push!(df, (;kind, name, bench))


name = "XML.LazyNode"
@info name
bench = @benchmark read($file, LazyNode)
push!(df, (;kind, name, bench))

name = "XML.Node"
@info name
bench = @benchmark read($file, Node)
push!(df, (;kind, name, bench))


name = "EzXML.readxml"
@info name
bench = @benchmark EzXML.readxml($file)
push!(df, (;kind, name, bench))


name = "XMLDict.xml_dict"
@info name
bench = @benchmark XMLDict.xml_dict(read($file, String))
push!(df, (;kind, name, bench))


#-----------------------------------------------------------------------------# Lazy Iteration
kind = "Lazy Iteration"

name = "for x in read(file, LazyNode); end"
@info name
bench = @benchmark (for x in read($file, LazyNode); end)
push!(df, (;kind, name, bench))


name = "for x in open(EzXML.StreamReader, file); end"
@info name
bench = @benchmark (reader = open(EzXML.StreamReader, $file); for x in reader; end; close(reader))
push!(df, (;kind, name, bench))


#-----------------------------------------------------------------------------# Lazy Iteration: Collect Tags
kind = "Collect Tags"

name = "via XML.LazyNode"
@info name
bench = @benchmark [tag(x) for x in o] setup=(o = read(file, LazyNode))
push!(df, (;kind, name, bench))


name = "via EzXML.StreamReader"
@info name
bench = @benchmark [r.name for x in r if x == EzXML.READER_ELEMENT] setup=(r=open(EzXML.StreamReader, file)) teardown=(close(r))
push!(df, (;kind, name, bench))


name = "via EzXML.readxml"
@info name
function get_tags(o::EzXML.Node)
    out = String[]
    for node in EzXML.eachelement(o)
        push!(out, node.name)
        for tag in get_tags(node)
            push!(out, tag)
        end
    end
    out
end
bench = @benchmark get_tags(o.root) setup=(o = EzXML.readxml(file))
push!(df, (;kind, name, bench))



#-----------------------------------------------------------------------------# Plots
function plot(df, kind)
    g = groupby(df, :kind)
    sub = g[(;kind)]
    x = map(row -> "$(row.kind): $(row.name)", eachrow(sub))
    y = map(x -> median(x).time / 1000^2, sub.bench)
    display(barplot(x, y, title = "$kind Time (ms)", border=:none, width=50))
end

plot(df, "Read")
plot(df, "Lazy Iteration")
plot(df, "Collect Tags")
