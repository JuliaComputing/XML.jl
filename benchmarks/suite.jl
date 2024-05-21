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

macro add_benchmark(kind, name, expr...)
    esc(:(let
        @info string($kind, " - ", $name)
        bench = @benchmark $(expr...)
        push!(df, (; kind=$kind, name=$name, bench))
    end))
end

#-----------------------------------------------------------------------------# Write
@add_benchmark "Write" "XML.write" XML.write($(tempname()), o) setup = (o = read(file, Node))
@add_benchmark "Write" "EzXML.writexml" EzXML.write($(tempname()), o) setup = (o = EzXML.readxml(file))

#-----------------------------------------------------------------------------# Read
@add_benchmark "Read" "XML.LazyNode" read($file, LazyNode)
@add_benchmark "Read" "XML.Node" read($file, Node)
@add_benchmark "Read" "EzXML.readxml" EzXML.readxml($file)
@add_benchmark "Read" "XMLDict.xml_dict" XMLDict.xml_dict(read($file, String))

#-----------------------------------------------------------------------------# Lazy Iteration
@add_benchmark "Lazy Iteration" "LazyNode" for x in read($file, LazyNode); end
@add_benchmark "Lazy Iteration" "EzXML.StreamReader" (reader = open(EzXML.StreamReader, $file); for x in reader; end; close(reader))

#-----------------------------------------------------------------------------# Lazy Iteration: Collect Tags
@add_benchmark "Collect Tags" "LazyNode" [tag(x) for x in o] setup = (o = read(file, LazyNode))
@add_benchmark "Collect Tags" "EzXML.StreamReader" [r.name for x in r if x == EzXML.READER_ELEMENT] setup=(r=open(EzXML.StreamReader, file)) teardown=(close(r))

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
@add_benchmark "Collect Tags" "EzXML.readxml" get_tags(o.root) setup=(o = EzXML.readxml(file))


#-----------------------------------------------------------------------------# Plots
function plot(df, kind)
    g = groupby(df, :kind)
    sub = g[(;kind)]
    x = map(row -> "$(row.name)", eachrow(sub))
    y = map(x -> median(x).time / 1000^2, sub.bench)
    display(barplot(x, y, title = "$kind Time (ms)", border=:none, width=50))
end

plot(df, "Read")
plot(df, "Write")
plot(df, "Lazy Iteration")
plot(df, "Collect Tags")
