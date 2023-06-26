
"""
Represents all possible values of a `Cron` time slice within a bit array.

For example:

    `00100100` can represent values `3,6` for slice `day_of_week`
    `00111100` can represent values `3-6` for slice `day_of_week`
    `00000001` can represent values `0` for slice `day_of_week`
    `00000001` can represent values `1` for slice `day_of_month`
    `11111111` can represent values `0-7` for slice `day_of_week`
"""
struct CronSlice{T<:Unsigned, MIN, MAX}
    bits::T

    function CronSlice{T, MIN, MAX}(x::T) where {T<:Unsigned, MIN, MAX}
        MIN >= 0 && MAX <= sizeof(T)*8 || error("Cannot create CronSlice in range [$MIN,$MAX]")
        return new(x)
    end
end

# Default Type
const TCronSlice = CronSlice{UInt, typemin(UInt), typemax(UInt)}


function CronSlice{T, MIN, MAX}(x::Int) where {T<:Unsigned, MIN, MAX}
    x >= MIN && x <= MAX || error("Cannot create CronSlice $x in range [$MIN,$MAX]")
    return CronSlice{T, MIN, MAX}(T(1) << x)
end

function CronSlice{T, MIN, MAX}(x::Symbol) where {T<:Unsigned, MIN, MAX}
    @assert x == :*
    return CronSlice{T, MIN, MAX}(typemax(T))
end

CronSlice{T, MIN, MAX}(x::Char) where {T<:Unsigned, MIN, MAX} = CronSlice{T, MIN, MAX}(Symbol(x))

"""
Parsing
For  example,  `"8-11"`  for  an  `hours' entry specifies execution at hours 8, 9, 10 and 11.
Lists are allowed.  A list is a set of numbers (or ranges) separated by commas.

Examples:
    `"1,2,5,9", "0-4,8-12", "*/2"`.

Step  values can be used in conjunction with ranges.
Following a range with `/<number>` specifies skips of the number's value through the range. 
For example, `"0-23/2"` can  be used  in the hours field to specify command execution every other hour (the alternative inthe V7 standard is `"0,2,4,6,8,10,12,14,16,18,20,22"`).
Steps are also permitted after an asterisk, so if you want to say `every two hours`, just use `"*/2"`.
"""
function CronSlice{T, MIN, MAX}(x::String) where {T<:Unsigned, MIN, MAX}
    m = match(r"^([\d\-\,]+|\*)(/(\d+))?$", value)
    if isnothing(m)
        error("Cannot parse CronSlice $x: not a crontab value format. Example: `1,2,5,9`, `0-4,8-12` or `*/2` ")
    end
    ranges = m.captures[1]
    step = m.captures[3]

    function parse_single_range(r::SubString{String})
        s = split(r, ',')
        a = parse(Int, s[1])
        b = parse(Int, s[2])
        if !(a >= MIN && a <= MAX) && !(b >= MIN && b <= MAX)
            error("Cannot create CronSlice from range [$a,$b] within limits [$MIN,$MAX]")
        end
        # Bit array with ones only between a and b (included)
        return CronSlice{T, MIN, MAX}()
    end

    # No step given, only work with ranges
    if isnothing(step)

    end

    step = parse(Int, step)
    step >= MIN && step <= MAX || error("Cannot create CronSlice, given step $step should be in range [$MIN,$MAX]")

end

"""
    next_slice(`00100000`, 0) == next_slice(`00100000`, 3) == 6 (assuming MIN is 0)
"""
function next_slice(c::CronSlice{T, MIN, MAX}, start)::Int where {T<:Unsigned, MIN, MAX}
    start >= MIN && start <= MAX || error("Cannot get cron slice $start in range [$MIN,$MAX]")
    mask = typemax(T) << start
    # Number of trailing zeros (+1 to take position of `1` into account) after the first one in `c.bits`, ignoring all ones before `start`
    return MIN + trailing_zeros(c.bits & mask) + 1 > MAX ? MIN : MIN + trailing_zeros(c.bits & mask) + 1
end

"""

This struct is inspired from unix crontab: https://manpages.ubuntu.com/manpages/lunar/en/man5/crontab.5.html

    field          allowed values
    -----          --------------
    second         0–59
    minute         0–59
    hour           0–23
    day of month   1–31
    month          1–12 (or names, see below)
    day of week    0–7 (0 or 7 is Sun, or use names)

A field may be an asterisk (*), which always stands for `first-last`.
Ranges of numbers are allowed.  Ranges are two  numbers  separated  with  a  hyphen.

The specified  range  is  inclusive.   
For  example,  `"8-11"`  for  an  `hours' entry specifies execution at hours 8, 9, 10 and 11.
Lists are allowed.  A list is a set of numbers (or ranges) separated by commas.

Examples:
    `"1,2,5,9", "0-4,8-12"`.

Step  values can be used in conjunction with ranges.
Following a range with `/<number>` specifies skips of the number's value through the range. 
For example, `"0-23/2"` can  be used  in the hours field to specify command execution every other hour (the alternative inthe V7 standard is `"0,2,4,6,8,10,12,14,16,18,20,22"`).
Steps are also permitted after an asterisk, so if you want to say `every two hours`, just use `"*/2"`.

Instead of mentionning the six fields, one of eight special methods may be used:

string         meaning
------         -------
yearly        Run once a year, `Cron(0,0,0,1,1,0)`
annually      (same as yearly)
monthly       Run once a month, `Cron(0,0,0,1,'*','*')`
weekly        Run once a week, `Cron(0,0,0,'*','*',1)`  
daily         Run once a day, `Cron(0,0,0,'*','*','*')`
midnight      (same as daily)
hourly        Run once an hour, `Cron(0,0,'*','*','*','*')`
once          Never repeat, `Cron(0,0,0,0,0,0)` 
"""
struct Cron
    ## All this can stored in 32 bytes (256 bits)
    second::CronSlice{UInt64,0,59}
    minute::CronSlice{UInt64,0,59}
    hour::CronSlice{UInt32,0,23}
    day_of_month::CronSlice{UInt32,1,31}
    month::CronSlice{UInt16,1,12}
    day_of_week::CronSlice{UInt8,0,7}

    function Cron(second, minute, hour, day_of_month, month, day_of_week)
        return new(
            CronSlice{UInt64,0,59}(second),
            CronSlice{UInt64,0,59}(minute),
            CronSlice{UInt32,0,23}(hour),
            CronSlice{UInt32,1,31}(day_of_month),
            CronSlice{UInt16,1,12}(month),
            CronSlice{UInt8,0,7}(day_of_week)
        )
    end
end

@inline yearly() = Cron(0,0,0,1,1,0)
@inline annually() = yearly()
@inline monthly() = Cron(0,0,0,1,'*','*')
@inline weekly() = Cron(0,0,0,'*','*',1)
@inline daily() = Cron(0,0,0,'*','*','*')
@inline midnight() = daily()
@inline hourly() = Cron(0,0,'*','*','*','*')
@inline once() = Cron(0,0,0,0,0,0)