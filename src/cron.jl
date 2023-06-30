
# Get day and month names (abreviated)
const MONTHS_OF_YEAR = Dict([
    name => idx for (idx,name) in
    enumerate(Dates.LOCALES["english"].months_abbr .|> lowercase)
])

const DAYS_OF_WEEK = Dict([
    name => idx for (idx,name) in
    enumerate(Dates.LOCALES["english"].days_of_week_abbr .|> lowercase)
])


"""
Represents all possible values of a `Cron` time slice within a bit array.

For example:

    `01001000` can represent values `3,6` for slice `day_of_week`
    `01111000` can represent values `3-6` for slice `day_of_week`
    `00000001` can represent values `0` for slice `day_of_week`
    `00000010` can represent values `1` for slice `day_of_week`
    `11111111` can represent values `0-7` for slice `day_of_week`
"""
struct CronSlice{T<:Unsigned, MIN, MAX}
    bits::T

    function CronSlice{T, MIN, MAX}(x::T) where {T<:Unsigned, MIN, MAX}
        # All bits outside of [MIN, MAX] will be ignored and turned to `0` in this constructor
        MIN >= 0 && MAX <= (sizeof(T)*8)-1 || error("Cannot create CronSlice of type $(typeof(x)) with range [$MIN,$MAX]")
        # For example for 0 bits and [MIN, MAX] = [3,6] the mask will be `01111000`
        mask = (typemax(T) << MIN) & (typemax(T) >> (sizeof(T)*8 - (MAX+1)))
        return new(x & mask)
    end
end

min(::CronSlice{T, MIN, MAX}) where {T<:Unsigned, MIN, MAX} = MIN
max(::CronSlice{T, MIN, MAX}) where {T<:Unsigned, MIN, MAX} = MAX

# Default Type
const TCronSlice = CronSlice{UInt, 0, (sizeof(UInt)*8)-1}


function CronSlice{T, MIN, MAX}(x::Int) where {T<:Unsigned, MIN, MAX}
    x >= MIN && x <= MAX || error("Cannot create CronSlice $x in range [$MIN,$MAX]")
    return CronSlice{T, MIN, MAX}(T(x))
end

function CronSlice{T, MIN, MAX}(x::Symbol) where {T<:Unsigned, MIN, MAX}
    x == :* || error("Cannot create CronSlice from a Symbol other than `*`")
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

Names  can also be used for the ``month'' and ``day of week'' fields.  Use the first three letters of the particular day or month (case doesn't matter).
Ranges or  lists  of  names are not allowed.
"""
function CronSlice{T, MIN, MAX}(x::String) where {T<:Unsigned, MIN, MAX}
    # First, Check that `x` is not simply a month or date name
    if haskey(DAYS_OF_WEEK, x)
        return CronSlice{T, MIN, MAX}(string(DAYS_OF_WEEK[x]))
    end
    if haskey(MONTHS_OF_YEAR, x)
        return CronSlice{T, MIN, MAX}(string(MONTHS_OF_YEAR[x]))
    end

    # Trim all white spaces
    rstrim = s -> join(map(c -> isspace(s[c]) ? "" : s[c], 1:length(s)))
    m = match(r"^([\d\-\,]+|\*)(/(\d+))?$", rstrim(x))
    if isnothing(m)
        error("Cannot parse CronSlice $x: not a crontab value format. Example: `1,2,5,9`, `0-4,8-12` or `*/2` ")
    end
    ranges = m.captures[1]
    step = m.captures[3]

    function parse_single_range(r::SubString{String})
        s = split(r, '-')
        # Case when the string is a number and not a range (or a star)
        try
            a = parse(Int, s[1])
        catch
            return CronSlice{T, MIN, MAX}(s[1][1]), MIN, MAX
        end

        if length(s) == 1
            b = a
        else
            b = parse(Int, s[2])
        end

        if !(a >= MIN && a <= MAX) && !(b >= MIN && b <= MAX)
            error("Cannot create CronSlice from range [$a,$b] within limits [$MIN,$MAX]")
        end
        a <= b || error("Cannot parse CronSlice $x: empty range [$a,$b]")
        # Bit array with ones only between a and b (included)
        mask = (typemax(T) << a) & (typemax(T) >> (sizeof(T)*8 - (b+1)))
        return CronSlice{T, MIN, MAX}(mask), a, b
    end

    function parse_ranges(rr::SubString{String})
        prev_a, prev_b = MIN, MIN
        # Value to return
        bits = T(0)
        for r in split(rr, ',')
            c2, a, b = parse_single_range(r)
            # Check that consecutive ranges are in increasing order
            prev_b <= a || error("Cannot parse CronSlice $x:, non increasing range from [$prev_a,$prev_b] to [$a,$b]")
            prev_a, prev_b = a, b
            # Merge bits from c and c2, no need for offseting as we are working with increasing ranges
            bits |= c2.bits
        end
        # Return also covering range (usefull for step)
        _, ori_a, _ = parse_single_range(split(rr, ',')[1])
        return bits, ori_a, prev_b
    end

    # No step given, only work with ranges
    if isnothing(step)
        bits, _, _ = parse_ranges(ranges)
        return CronSlice{T, MIN, MAX}(bits)
    end

    step = parse(Int, step)

    if step == 0
        # Empty CronSlice
        return CronSlice{T, MIN, MAX}(T(0))
    end

    step >= 0 && step <= MAX || error("Cannot parse CronSlice $x:, given step $step should be in range [0,$MAX]")
    bits, a, b = parse_ranges(ranges)
    # x/y means taking each yth other values of x
    # 0-10/3 = [0,3,6,9]
    # So the mask would be `01001001` in 8 bits (0-7/3)
    step_mask = T(1)
    for i ∈ a:Int(floor(b/step))
        step_mask |= T(1) << (step*i)
    end
    return CronSlice{T, MIN, MAX}(bits & (step_mask << a))

end

"""
    next_slice(`00100000`, 0) == next_slice(`00100000`, 3) == 6 (assuming MIN is 0)
"""
function next_slice(c::CronSlice{T, MIN, MAX}, start)::Int where {T<:Unsigned, MIN, MAX}
    start >= MIN && start <= MAX || error("Cannot get cron slice $start in range [$MIN,$MAX]")
    mask = typemax(T) << start
    # Position of the next `1` after `start`
    # Return `-1` (neutral value) if c.bits is only zeros
    return trailing_zeros(c.bits & mask) > MAX ? -1 : trailing_zeros(c.bits & mask)
    #return MIN + trailing_zeros(c.bits & mask) + 1 > MAX ? MIN : MIN + trailing_zeros(c.bits & mask) + 1
end

"""
    Custom iterator for CronSlice
Advance the iterator to obtain the next element. If no elements remain, nothing should be returned. Otherwise, a 2-tuple of the next element and the new iteration state should be returned.
"""
function Base.iterate(c::CronSlice{T, MIN, MAX}, state) where {T<:Unsigned, MIN, MAX}
    if !(state >= MIN && state <= MAX)
        # Stop signal
        return nothing
    end
    next = next_slice(c, state)
    if next == -1
        return nothing
    end
    return next, next + 1
end

function Base.iterate(c::CronSlice{T, MIN, MAX}) where {T<:Unsigned, MIN, MAX}
    return Base.iterate(c, MIN)
end

function Base.collect(c::CronSlice{T, MIN, MAX})::Vector{Int} where {T<:Unsigned, MIN, MAX}
    v = Vector{Int}()
    for slice in c
        push!(v, slice)
    end
    return v
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

Names  can also be used for the ``month'' and ``day of week'' fields.  Use the first three letters of the particular day or month (case doesn't matter).
Ranges or  lists  of  names are not allowed.

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
    dayofmonth::CronSlice{UInt32,1,31}
    month::CronSlice{UInt16,1,12}
    dayofweek::CronSlice{UInt8,0,7}

    function Cron(second, minute, hour, dayofmonth, month, dayofweek)
        return new(
            CronSlice{UInt64,0,59}(second),
            CronSlice{UInt64,0,59}(minute),
            CronSlice{UInt32,0,23}(hour),
            CronSlice{UInt32,1,31}(dayofmonth),
            CronSlice{UInt16,1,12}(month),
            CronSlice{UInt8,0,7}(dayofweek)
        )
    end
end

# Every year, at Junary First
@inline yearly() = Cron("0","0","0","1","1","*")
@inline annually() = yearly()
@inline monthly() = Cron("0","0","0","1",'*','*')
@inline weekly() = Cron("0","0","0",'*','*',"1")
@inline daily() = Cron("0","0","0",'*','*','*')
@inline midnight() = daily()
@inline hourly() = Cron("0","0",'*','*','*','*')
@inline once() = Cron("0","0","0","0","0","0")

# Used to jump to next date, see: https://docs.julialang.org/en/v1/stdlib/Dates/#Dates.tonext-Tuple{Function,%20TimeType}
for (symbl, stepkind) in [
    (:second, :Second),
    (:minute, :Minute),
    (:hour, :Hour),
    (:dayofmonth, :Day),
    (:month, :Month),
    (:dayofweek, :Day)
]
    @eval function $(Symbol("tonext_$symbl"))(dt::DateTime, c::Cron)::DateTime
        # Closet slice to `symbl`
        next = next_slice(c.$symbl, Dates.$symbl(dt))
        # No slice after, Dates.symlb, take first slice
        if next == -1
            next = next_slice(c.$symbl, min(c.$symbl))
        end
        # This can happen if c.symbl is empty, if so, we return unaltered dt
        # Also return unaltered `dt` if we stay on the same slice
        if next == -1 || Dates.$symbl(dt) == next
            return dt
        else
            return Dates.tonext(d -> Dates.$symbl(d) == next, dt; step = Dates.$stepkind(1))
        end
    end
end

"""
@inline function tonext_month(dt::DateTime, c::Cron)::DateTime
    # Closet slice to  Dates.dayofweek(dt)
    next = next_slice(c.month, Dates.month(dt))
    # No slice after, Dates.dayofweek(dt), take first slice
    if next == -1
        next = next_slice(c.month, min(c.month))
    end

    if next == -1
        return dt
    else
        return Dates.tonext(d -> Dates.month(d) == next, dt)
    end
end
"""


function Dates.tonext(dt::DateTime, c::Cron)
    # Advance of at least 1 second
    # This prevents Dates.tonext("2023-07-07T00:00:00", daily()) == "2023-07-07T00:00:00"
    # This will force the overflow to the next day
    dt = dt + Dates.Second(1)
    # Jump to next timestamp in increasing time delta order
    dt = tonext_second(dt, c)
    dt = tonext_minute(dt, c)
    dt = tonext_hour(dt, c)
    dt = tonext_dayofmonth(dt, c)
    dt = tonext_dayofweek(dt, c)
    dt = tonext_month(dt, c)
    # TODO: set milliseconds to 0 ?
    return dt
end

"""
    nnext(dt::DateTime, c::Cron, n::Int)::Vector{DateTime}

Return the list of the next `n` dates following the Cron `c` pattern.
"""
function nnext(dt::DateTime, c::Cron, n::Int)::Vector{DateTime}
    v = Vector{DateTime}()
    for i ∈ 1:n
        dt = Dates.tonext(dt, c)
        push!(v, dt)
    end
    return v
end