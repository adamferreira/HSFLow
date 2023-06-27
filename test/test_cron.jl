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
once,
nnext

using Test
using Dates

@testset "CronSlice" begin
    c = CronSlice{UInt8,0,7}(parse(UInt8, "00100100"; base=2))
    @test bitstring(c.bits) == "00100100"
    @test next_slice(c, 0) == 2
    @test next_slice(c, 1) == 2
    @test next_slice(c, 2) == 2
    @test next_slice(c, 3) == 5
    # Neutral value, no more 1 after pos 6
    @test next_slice(c, 7) == -1
    @test_throws ErrorException next_slice(c, 9)
    # 1 in front
    c = CronSlice{UInt8,0,7}(parse(UInt8, "10000000"; base=2))
    @test next_slice(c, 0) == 7
    @test next_slice(c, 3) == 7
    @test next_slice(c, 7) == 7
    # 1 in back
    c = CronSlice{UInt8,0,7}(parse(UInt8, "00000001"; base=2))
    @test next_slice(c, 0) == 0
    # Empty value
    c = CronSlice{UInt8,0,7}(parse(UInt8, "00000000"; base=2))
    @test next_slice(c, 0) == -1
    @test next_slice(c, 7) == -1
    # Empty value
    c = CronSlice{UInt8,1,7}(parse(UInt8, "00000000"; base=2))
    @test next_slice(c, 1) == -1
    @test next_slice(c, 7) == -1
    # Min/Max value error
    c = CronSlice{UInt8,2,6}(parse(UInt8, "00000001"; base=2))
    @test_throws ErrorException next_slice(c, 1)
    @test_throws ErrorException next_slice(c, 7)
    @test_throws ErrorException next_slice(c, 8)
    # Min/Max overflow
    @test_throws ErrorException CronSlice{UInt8,0,8}(0)
    @test_throws ErrorException CronSlice{UInt8,-1,7}(0)
    # Ignored bits relative to [MIN, MAX]
    c = CronSlice{UInt8,0,7}(parse(UInt8, "11111111"; base=2))
    @test bitstring(c.bits) == "11111111"
    c = CronSlice{UInt8,3,6}(parse(UInt8, "11111111"; base=2))
    @test bitstring(c.bits) == "01111000"
    c = CronSlice{UInt8,1,7}(parse(UInt8, "00000001"; base=2))
    @test bitstring(c.bits) == "00000000"
end

@testset "CronSlice iteration" begin
    c = CronSlice{UInt8,0,7}(parse(UInt8, "01001000"; base=2))
    expected = [3, 6]
    observed = []
    for slice in c
        push!(observed, slice)
    end
    @test observed == expected
    @test collect(c) == expected

    @test collect(CronSlice{UInt8,0,7}(parse(UInt8, "10000000"; base=2))) == [7]
    @test collect(CronSlice{UInt8,0,7}(parse(UInt8, "00000001"; base=2))) == [0]
    # First MIN bits are ignored
    @test collect(CronSlice{UInt8,1,7}(parse(UInt8, "00000001"; base=2))) == []
    @test collect(CronSlice{UInt8,1,7}(parse(UInt8, "00000011"; base=2))) == [1]
    # Limited range
    @test collect(CronSlice{UInt8,3,6}(parse(UInt8, "11111111"; base=2))) == [3,4,5,6]
    @test collect(CronSlice{UInt8,3,6}(parse(UInt8, "01111000"; base=2))) == [3,4,5,6]
end

@testset "CronSlice parse" begin
    T = CronSlice{UInt64,0,63}
    # All
    @test collect(T('*')) == collect(0:63)
    @test collect(T(:*)) == collect(0:63)
    # Names
    @test T("mon").bits == T("1").bits
    @test T("jan").bits == T("1").bits
    @test T("sun").bits == T("7").bits
    @test T("mar").bits == T("3").bits
    @test T("sep").bits == T("9").bits
    # Scalars
    @test collect(T("3")) == [3]
    @test collect(T("6")) == [6]
    @test collect(T("3,6,30,63")) == [3,6,30,63]
    @test collect(CronSlice{UInt8,0,7}("*")) == [0,1,2,3,4,5,6,7]
    @test_throws ErrorException T("6,3")
    @test_throws ErrorException T("toto")
    @test_throws ErrorException T("?,5-10")
    # Ranges
    @test collect(T("3-6")) == [3,4,5,6]
    @test collect(T("1,3-6")) == [1,3,4,5,6]
    @test collect(T("3-6, 55-60, 63")) == [3,4,5,6,55,56,57,58,59,60,63]
    @test_throws ErrorException T("6-3")
    @test_throws ErrorException T("3-6, 2-8")
    @test_throws ErrorException T("3-6, 2")
    # Steps
    @test collect(T("0-7/3")) == [0,3,6]
    @test collect(T("1-7/3")) == [1,4,7]
    @test collect(T("0-7/1")) == [0,1,2,3,4,5,6,7]
    @test collect(T("0-7/0")) == []
    @test collect(T("0-20,50-57,60,61,62/10")) == [0,10,20,50,60]
    @test collect(CronSlice{UInt8,0,7}("*/3")) == collect(CronSlice{UInt8,0,7}("0-7/3"))
    @test collect(CronSlice{UInt32,0,23}("*/4")) == [0,4,8,12,16,20]
    @test_throws ErrorException T("*/-1")
    @test_throws ErrorException T("*/100")
    @test_throws ErrorException T("*/")
end

@testset "Cron Dates" begin
    dt = DateTime("2023-07-06T18:15:00")

    # Basic Crons
    @test Dates.tonext(dt, hourly()) == DateTime("2023-07-06T19:00:00")
    @test Dates.tonext(dt, daily()) == DateTime("2023-07-07T00:00:00")
    @test Dates.tonext(dt, midnight()) == DateTime("2023-07-07T00:00:00")
    @test Dates.tonext(DateTime("2023-07-07T00:00:00"), daily()) == DateTime("2023-07-08T00:00:00")
    @test Dates.tonext(dt, weekly()) == DateTime("2023-07-10T00:00:00")
    @test Dates.tonext(dt, monthly()) == DateTime("2023-08-01T00:00:00")
    @test Dates.tonext(dt, yearly()) == DateTime("2024-01-01T00:00:00")
    @test Dates.tonext(dt, annually()) == DateTime("2024-01-01T00:00:00")

    # Cron syntax examples: https://manpages.ubuntu.com/manpages/lunar/en/man5/crontab.5.html
    # Run five minutes after midnight, every day
    @test Dates.tonext(dt, Cron("0","5","0","*","*","*")) == DateTime("2023-07-07T00:05:00")
    # Run at 2:15pm on the first of every month — output mailed to paul
    @test Dates.tonext(dt, Cron("0","15","14","1","*","*")) == DateTime("2023-08-01T14:15:00")
    # Run at 10 pm on weekdays, annoy Joe
    @test Dates.tonext(dt, Cron("0","0","22","*","*","1-5")) == DateTime("2023-07-06T22:00:00")
    # -> The mail will arrive on monday at 10pm
    @test Dates.tonext(DateTime("2023-07-08T18:15:00"), Cron("0","0","22","*","*","1-5")) == DateTime("2023-07-10T22:00:00")
    # Run 23 minutes after midn, 2am, 4am ..., everyday
    @test nnext(dt, Cron("0","23","0-23/2","*","*","*"), 5) == [
        DateTime("2023-07-06T18:23:00"),
        DateTime("2023-07-06T20:23:00"),
        DateTime("2023-07-06T22:23:00"),
        DateTime("2023-07-07T00:23:00"),
        DateTime("2023-07-07T02:23:00")
    ]
    # Run at 5 after 4 every Sunday
    @test nnext(dt, Cron("0","5","4","*","*","sun"), 3) == [
        DateTime("2023-07-09T04:05:00"),
        DateTime("2023-07-16T04:05:00"),
        DateTime("2023-07-23T04:05:00")
    ]
    # Run every 4th hour on the 1st Monday of the month
    # TODO: is it : on the 1st Monday of each month 4hr apart ?
    #@test nnext(dt, Cron("0","0","*/4","1","*","mon"), 3) == [
    #    DateTime("2023-08-07T20:00:00"),
    #    DateTime("2023-09-04T00:00:00"),
    #    DateTime("2023-10-02T04:00:00")
    #]
    # Run at midn on every Sunday that's an uneven date"
    @test nnext(dt, Cron("0","0","0","*/2","*","sun"), 5) == [
        DateTime("2023-07-09T00:00:00"),
        DateTime("2023-07-16T00:00:00"),
        DateTime("2023-07-23T00:00:00"),
        DateTime("2023-07-30T00:00:00"),
        DateTime("2023-08-06T00:00:00")
    ]
    # Run every minute starting at 1 p.m. and ending at 1:05 p.m., every day
    @test nnext(dt, Cron("0","0-5","13","*","*","*"), 10) == [
        DateTime("2023-07-07T13:00:00"),
        DateTime("2023-07-07T13:01:00"),
        DateTime("2023-07-07T13:02:00"),
        DateTime("2023-07-07T13:03:00"),
        DateTime("2023-07-07T13:04:00"),
        DateTime("2023-07-07T13:05:00"),
        DateTime("2023-07-08T13:00:00"),
        DateTime("2023-07-08T13:01:00"),
        DateTime("2023-07-08T13:02:00"),
        DateTime("2023-07-08T13:03:00")
    ]
    # Run every 15 minutes starting at 1 p.m. and ending at 1:55 p.m. and then starting at 6 p.m. and ending at 6:55 p.m., every day
    # Here it'll start at 18:30 as it's already 18:15
    @test nnext(dt, Cron("0","*/15","13,18","*","*","*"), 10) == [
        DateTime("2023-07-06T18:30:00"),
        DateTime("2023-07-06T18:45:00"),
        DateTime("2023-07-07T13:00:00"),
        DateTime("2023-07-07T13:15:00"),
        DateTime("2023-07-07T13:30:00"),
        DateTime("2023-07-07T13:45:00"),
        DateTime("2023-07-07T18:00:00"),
        DateTime("2023-07-07T18:15:00"),
        DateTime("2023-07-07T18:30:00"), 
        DateTime("2023-07-07T18:45:00")
    ]
    # Run every monday at 8am and 6pm
    @test nnext(dt, Cron("0","0","8,18","*","*","mon"), 4) == [
        DateTime("2023-07-10T08:00:00"),
        DateTime("2023-07-10T18:00:00"),
        DateTime("2023-07-17T08:00:00"),
        DateTime("2023-07-17T18:00:00")
    ]
end