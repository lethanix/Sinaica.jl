import Sinaica
using Test
using Revise

@testset "Sinaica.jl" begin
    data = Sinaica.data
    stationsData = Sinaica.stationsData("San Luis Potosí")
    @test isempty(data) == false
    @test isempty(stationsData) == false
end
