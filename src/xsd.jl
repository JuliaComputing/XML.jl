function generate_julia(input::AbstractString, output::AbstractString = joinpath(@__DIR__, "generated.jl"))
    doc = document(input)
    open(touch(output), "w") do io
        for element in root(doc).children
            tag = element.tag
            if tag == "simpleType" || "xsd:simpleType"
                T = uppercasefirst(element.attributes[:])
            end
        end
    end
    output
end
