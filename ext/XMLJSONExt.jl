module XMLJSONExt

using JSON
using OrderedCollections
using XML

function XML.xml2dicts(node::Node)
    if nodetype(node) == XML.Document
        # root node has no tag and 1 child, so it is special, just apply to its child
        return XML.xml2dicts(only(node.children))
    elseif nodetype(node) == XML.Text
        # text nodes have no tag, and just have contents
        return OrderedDict("_" => node.value)
    elseif nodetype(node) == XML.Element
        # normal case
        dict = OrderedDict{String,Any}()
        # first put in the attributes
        if !isnothing(attributes(node))
            merge!(dict, attributes(node))
        end
        # then any children
        for child in children(node)
            child_result = XML.xml2dicts(child)
            for (key, value) in child_result
                if haskey(dict, key)
                    if isa(dict[key], Vector)
                        push!(dict[key], value)
                    else
                        dict[key] = [dict[key], value]
                    end
                else
                    dict[key] = value
                end
            end
        end
        return OrderedDict(tag(node) => dict)
    else
        throw(DomainError(nodetype(node), "unsupported node type"))
    end
end



function XML.xml2json(xml::Node, json="")
    dict_result = XML.xml2dicts(xml)

    if isdir(dirname(json))
        open(json, "w") do io
            JSON.print(io, dict_result, 2)
        end
    else
        return JSON.json(dict_result)
    end
end

XML.xml2json(xml::IO, json="") = XML.xml2json(read(xml, String), json)

end # module
