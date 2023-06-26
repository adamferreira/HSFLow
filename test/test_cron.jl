using HSFlow: 
CronSlice,
Cron,
next_slice,
yearly,
annually,
monthly,
weekly,
daily,
midnight,
hourly,
once

using Test

@testset "CronSlice" begin
    c = CronSlice{UInt8,0,7}(parse(UInt8, "00100100"; base=2))
    @test bitstring(c.bits) == "00100100"
    @test next_slice(c, 0) == 3
    @test next_slice(c, 1) == 3
    @test next_slice(c, 2) == 3
    @test next_slice(c, 3) == 6
    # Neutral value, no more 1 after pos 6
    @test next_slice(c, 7) == 0
    @test_throws ErrorException next_slice(c, 9)
    # 1 in front
    c = CronSlice{UInt8,0,8}(parse(UInt8, "10000000"; base=2))
    @test next_slice(c, 0) == 8

    # Min/Max value error
    c = CronSlice{UInt8,2,6}(parse(UInt8, "00000001"; base=2))
    @test_throws ErrorException next_slice(c, 1)
    @test_throws ErrorException next_slice(c, 7)
    @test_throws ErrorException next_slice(c, 8)
    # Min/Max overflow
    @test_throws ErrorException CronSlice{UInt8,0,9}(0)
    @test_throws ErrorException CronSlice{UInt8,-1,7}(0)
end