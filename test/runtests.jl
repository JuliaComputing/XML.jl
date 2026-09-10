using Test

# Every testset of the suite runs under one parent testset, so a failure or error in one does not
# abort the rest, and the summary at the end aggregates them all before throwing once. The body
# lives in its own file, included from inside the parent: `include` evaluates it statement by
# statement at top level, so each `@testset` stays its own top-level thunk (one `@testset begin …
# end` block around the whole body would compile it as a single thunk, pathologically slowly), and
# a nested testset finds its parent dynamically, whichever way the Test stdlib keeps track of it.
@testset "XML.jl" begin
    include("suite.jl")
end
