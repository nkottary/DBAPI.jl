module DBAPIBase

using Compat

export cursor,
    execute!,
    executemany!,
    commit,
    rollback,
    rows,
    columns,
    connection,
    fetchintoarray!,
    fetchintorows!,
    fetchintocolumns!,
    DatabaseFetcher,
    interface,
    DatabaseInterface,
    DatabaseError,
    DatabaseConnection,
    DatabaseCursor,
    FixedLengthDatabaseCursor,
    DatabaseQuery,
    DatabaseQueryError


import Base: connect, close, getindex, isopen, show, start, next, done, length, isempty

import Iterators: imap

abstract DatabaseInterface
abstract DatabaseError{T<:DatabaseInterface} <: Exception
abstract DatabaseConnection{T<:DatabaseInterface}
abstract DatabaseCursor{T<:DatabaseInterface}
abstract FixedLengthDatabaseCursor{T} <: DatabaseCursor{T}
if VERSION >= v"0.4.0"
    Base.linearindexing(::Type{FixedLengthDatabaseCursor}) = Base.LinearSlow()
end
Base.ndims(cursor::FixedLengthDatabaseCursor) = 2

abstract DatabaseQuery

@compat immutable StringDatabaseQuery{T<:AbstractString} <: DatabaseQuery
    query::T
end

function show(io::IO, connection::DatabaseConnection)
    print(io, typeof(connection), "(closed=$(!isopen(connection)))")
end

function show(io::IO, cursor::DatabaseCursor)
    print(io, typeof(cursor), "(", connection(cursor), ")")
end

"""
Returns the interface type for any database object.
"""
@compat function interface{T<:DatabaseInterface}(
    database_object::Union{DatabaseCursor{T}, DatabaseConnection{T}, DatabaseError{T}}
)
    return T
end

"""
If this error is thrown, a driver has not implemented a required function
of this interface.
"""
type NotImplementedError{T<:DatabaseInterface} <: DatabaseError{T} end
function Base.showerror{T<:DatabaseInterface}(io::IO, e::NotImplementedError{T})
    print(io, T, " does not implement this required DBAPI feature")
end

"""
If this error is thrown, a user has attempted to use an optional function
of this interface which the driver does not implement.
"""
type NotSupportedError{T<:DatabaseInterface} <: DatabaseError{T} end
function Base.showerror{T<:DatabaseInterface}(io::IO, e::NotSupportedError{T})
    print(io, T, " does not support this optional DBAPI feature")
end

"""
If this error is thrown, an error occured while processing this database query.
"""
type DatabaseQueryError{T<:DatabaseInterface, S<:DatabaseQuery} <: DatabaseError{T}
    interface::Type{T}
    query::S
end

function Base.showerror{T<:DatabaseInterface}(io::IO, e::DatabaseQueryError{T})
    print(io, "An error occured while processing this query:\n", e.query)
end

"""
Constructs a database connection.

Returns `connection::DatabaseConnection`.
"""
function connect{T<:DatabaseInterface}(::Type{T}, args...; kwargs...)
    throw(NotImplementedError{T}())
end

"""
Close the connection now (rather than when the finalizer is called).

Any further attempted operations on the connection or its cursors will throw a
subtype of DatabaseError.

Closing a connection without committing will cause an implicit rollback to be
performed.

Returns `nothing`.
"""
function close{T<:DatabaseInterface}(conn::DatabaseConnection{T})
    throw(NotImplementedError{T}())
end

"""
Returns true if the connection is open and not broken.

Returns `Bool`
"""
function isopen{T<:DatabaseInterface}(conn::DatabaseConnection{T})
    throw(NotImplementedError{T}())
end

"""
Commit any pending transaction to the database.

Dataase drivers that do not support transactions should implement this
function with no body.

Returns `nothing`.
"""
function commit{T<:DatabaseInterface}(conn::DatabaseConnection{T})
    throw(NotImplementedError{T}())
end

"""
Roll back to the start of any pending transaction.

Database drivers that do not support transactions may not implement this
function.

Returns `nothing`.
"""
function rollback{T<:DatabaseInterface}(conn::DatabaseConnection{T})
    throw(NotSupportedError{T}())
end

"""
Constructs a database connection, runs `func` on that connection, and ensures the
connection is closed after `func` completes or errors.

Returns the result of calling `func`.
"""
function connect{T<:DatabaseInterface}(func::Function, ::Type{T}, args...; kwargs...)
    conn = connect(T, args...; kwargs...)

    try
        return func(conn)
    finally
        try
            close(conn)
        catch e
            warn(e)
        end
    end
end

"""
Create a new database cursor.

If the database does not implement cursors, the driver must implement a cursor
object which emulates cursors to the extent required by the interface.

Some drivers may implement multiple cursor types, but all must follow the
`DatabaseCursor` interface. Additional arguments may be given to the
driver's implementation of `cursor` but this method must be implemented with
reasonable defaults.

Returns `DatabaseCursor{T}`.
"""
function cursor{T<:DatabaseInterface}(conn::DatabaseConnection{T})
    throw(NotImplementedError{T}())
end

"""
Return the corresponding connection for a given cursor.

Returns `DatabaseConnection{T}`.
"""
function connection{T<:DatabaseInterface}(cursor::DatabaseCursor{T})
    throw(NotImplementedError{T}())
end

"""
Run a query on a database.

The results of the query are not returned by this function but are accessible
through the cursor.

`parameters` can be any iterable of positional parameters, or of some
T<:Associative for keyword/named parameters.

Returns `nothing`.
"""
function execute!{T<:DatabaseInterface}(
        cursor::DatabaseCursor{T},
        query::DatabaseQuery,
        parameters=(),
    )
    throw(NotImplementedError{T}())
end

function execute!{T<:DatabaseInterface}(
        cursor::DatabaseCursor{T},
        query::AbstractString,
        parameters=(),
    )
    execute!(cursor, StringDatabaseQuery(query), parameters)
end

"""
Run a query on a database multiple times with different parameters.

The results of the queries are not returned by this function. The result of
the final query run is accessible by the cursor.

`parameters` can be any iterable of a set of any iterables of positional
parameters, or items of some T<:Associative for keyword/named parameters.

Returns `nothing`.
"""
function executemany!{T<:DatabaseInterface}(
        cursor::DatabaseCursor{T},
        query::DatabaseQuery,
        parameters=(),
    )
    for parameter_set in parameters
        result = execute!(cursor, query, parameter_set)
    end

    return nothing
end

function executemany!{T<:DatabaseInterface}(
        cursor::DatabaseCursor{T},
        query::AbstractString,
        parameters=(),
    )
    executemany!(cursor, StringDatabaseQuery(query), parameters)
end

"""
Create a row iterator.

This method should return an instance of an iterator type which returns one row
on each iteration. Each row should be returned as a Tuple{...} with as much
type information in the Tuple{...} as possible. It is encouraged but not
necessary to have the rows be of the same type.
"""
function rows{T<:DatabaseInterface}(cursor::DatabaseCursor{T})
    throw(NotImplementedError{T}())
end

"""
Create a column iterator.

This method should return an instance of an iterator type which returns one
column on each iteration. Each column should be returned as a Vector{...} with
as much type information in the Vector{...} as possible.

This method is optional if rows can have different lengths or sets of values.
"""
function columns{T<:DatabaseInterface}(cursor::DatabaseCursor{T})
    throw(NotSupportedError{T}())
end

"""
Get result value from a database cursor.

This method gets a single result value in row `i` in column `j`.

This method is optional if rows or columns do not have a defined order.
"""
function getindex{T<:DatabaseInterface}(cursor::FixedLengthDatabaseCursor{T}, i::Integer, j::Integer)
    throw(NotImplementedError{T}())
end

"""
Get result value from a database cursor.

This method gets a single result value in row `i` in column named `col`.

This method is optional if rows do not have a defined order or if columns do
not have names.
"""
function getindex{T<:DatabaseInterface}(cursor::FixedLengthDatabaseCursor{T}, i::Integer, col::Symbol)
    throw(NotImplementedError{T}())
end

"""
Get result value from a database cursor.

This method gets a single result value in row named `row` in column `j`.

This method is optional if rows do not have names/keys or if columns do not
have a defined order.
"""
function getindex{T<:DatabaseInterface}(cursor::FixedLengthDatabaseCursor{T}, row::Symbol, j::Integer)
    throw(NotImplementedError{T}())
end

"""
Get result value from a database cursor.

This method gets a single result value in row named `row` in column named `col`.

This method is optional if rows do not have names/keys or if columns do not
have names.
"""
function getindex{T<:DatabaseInterface}(cursor::FixedLengthDatabaseCursor{T}, row::Symbol, col::Symbol)
    throw(NotImplementedError{T}())
end

"""
Get result value from a database cursor.

This method gets a single result value in row indexed by `row` in column
indexed by `col`.

Any other row or column index types are optional.
"""
function getindex{T<:DatabaseInterface}(cursor::FixedLengthDatabaseCursor{T}, row::Any, col::Any)
    throw(NotImplementedError{T}())
end

"""
Get result value from a database cursor.

Indexing is not required for types which don't subtype
FixedLengthDatabaseCursor.
"""
function getindex{T<:DatabaseInterface}(cursor::DatabaseCursor{T}, row::Any, col::Any)
    throw(NotSupportedError{T}())
end

"""
Get the number of rows available from a database cursor.

Returns `Int`
"""
function length{T<:DatabaseInterface}(cursor::FixedLengthDatabaseCursor{T})
    throw(NotImplementedError{T}())
end

"""
Get the number of rows available from a database cursor.

`length` is not required for types which don't subtype
FixedLengthDatabaseCursor.
"""
function length{T<:DatabaseInterface}(cursor::DatabaseCursor{T})
    throw(NotSupportedError{T}())
end

"""
A terrible hack to make the fetchintoarray! signature work.

See https://github.com/JuliaLang/julia/issues/13156#issuecomment-140618981
"""
typealias AssociativeVK{V, K} Associative{K, V}

index_return_type(a::Associative) = valtype(a)
index_return_type(a::Any) = eltype(a)

each_index_tuple(a::Associative) = eachindex(a)
each_index_tuple(a::Any) = imap(ind -> ind2sub(a, ind), eachindex(a))

"""
Get results from a database cursor and store them in a preallocated
two-dimensional data structure.

This out-of-the-box method supports a huge variety of data structures under the
`AbstractArray` and `Associative` supertypes. It uses the `getindex` functions
defined above.

When 2d indexing is used on an `Associative`, the result is usually tuple keys.

Returns the preallocated data structure.
"""
@compat function fetchintoarray!{T<:DatabaseInterface}(
        preallocated::Union{AbstractArray, Associative},
        cursor::FixedLengthDatabaseCursor{T},
        offset::Int=0,
    )

    offset_row = offset

    for (row, column) in each_index_tuple(preallocated)
        offset_row = row + offset
        datum = cursor[offset_row, column]
        preallocated[row, column] = (
            isa(datum, Nullable) &&
            !(index_return_type(preallocated) <: Nullable ||
                Nullable <: index_return_type(preallocated)) ?
            get(datum) :
            datum
        )
    end

    return preallocated, offset_row
end

"""
Get results from a database cursor and store them in a preallocated vector.

This out-of-the-box method supports a huge variety of data structures under the
`AbstractVector` supertype. It uses the `getindex` functions defined above.

Returns the preallocated vector.
"""
function fetchintoarray!{T<:DatabaseInterface}(
        preallocated::AbstractVector,
        cursor::FixedLengthDatabaseCursor{T},
        offset::Int=0,
    )

    offset_row = offset

    for row in eachindex(preallocated)
        offset_row = row + offset
        datum = cursor[offset_row, 1]
        preallocated[row] = (
            isa(datum, Nullable) &&
            !(index_return_type(preallocated) <: Nullable ||
                Nullable <: index_return_type(preallocated)) ?
            get(datum) :
            datum
        )
    end

    return preallocated, offset_row
end

"""
Get results from a database cursor and store them in a preallocated data
structure (a collection of rows).

This out-of-the-box method supports a huge variety of data structures under the
`AbstractArray` and `Associative` supertypes. It uses the `getindex` functions
defined above.

Returns the preallocated data structure.
"""
@compat function fetchintorows!{T<:DatabaseInterface, U<:Union{AbstractArray, Associative}}(
        preallocated::Union{AbstractArray{U}, AssociativeVK{U}},
        cursor::FixedLengthDatabaseCursor{T},
        offset::Int=0,
    )

    offset_row = offset

    for row in eachindex(preallocated)
        offset_row = row + offset

        for column in eachindex(preallocated[row])
            datum = cursor[offset_row, column]
            preallocated[row][column] = (
                isa(datum, Nullable) && !(index_return_type(preallocated[row]) <: Nullable) ?
                get(datum) :
                datum
            )
        end
    end

    return preallocated, offset_row
end

"""
Get results from a database cursor and store them in a preallocated data
structure (a collection of columns).

This out-of-the-box method supports a huge variety of data structures under the
`AbstractArray` and `Associative` supertypes. It uses the `getindex` functions
defined above.

`offset` represents the offset into the cursor denoting where to start fetching
data.

Returns the preallocated data structure.
"""
@compat function fetchintocolumns!{T<:DatabaseInterface, U<:Union{AbstractArray, Associative}}(
        preallocated::Union{AbstractArray{U}, AssociativeVK{U}},
        cursor::FixedLengthDatabaseCursor{T},
        offset::Int=0,
    )

    offset_row = offset

    for column in eachindex(preallocated), row in eachindex(preallocated[column])
        offset_row = row + offset
        datum = cursor[offset_row, column]
        preallocated[column][row] = (
            isa(datum, Nullable) && !(index_return_type(preallocated[row]) <: Nullable) ?
            get(datum) :
            datum
        )
    end

    return preallocated, offset_row
end

@compat function fetchintoarray!{T<:DatabaseInterface}(
        preallocated::Union{AbstractArray, Associative},
        cursor::DatabaseCursor{T},
        offset::Int=0,
    )

    throw(NotSupportedError{T}())
end

@compat function fetchintorows!{T<:DatabaseInterface, U<:Union{AbstractArray, Associative}}(
        preallocated::Union{AbstractArray{U}, AssociativeVK{U}},
        cursor::DatabaseCursor{T},
        offset::Int=0,
    )

    throw(NotSupportedError{T}())
end

@compat function fetchintocolumns!{T<:DatabaseInterface, U<:Union{AbstractArray, Associative}}(
        preallocated::Union{AbstractArray{U}, AssociativeVK{U}},
        cursor::DatabaseCursor{T},
        offset::Int=0,
    )

    throw(NotSupportedError{T}())
end

@compat typealias Orientation Union{Val{:rows}, Val{:columns}, Val{:array}}

@compat immutable DatabaseFetcher{O<:Orientation, T<:DatabaseInterface, U<:Union{AbstractArray, Associative}}
    orientation::O
    preallocated::U
    cursor::FixedLengthDatabaseCursor{T}
end

@compat function DatabaseFetcher{T, U}(
    # this is the actual required type for the `preallocated` field,
    # however there is no way to express that through parameters in the
    # type definition
        orientation::Symbol,
        preallocated::Union{AbstractArray{U}, AssociativeVK{U}},
        cursor::FixedLengthDatabaseCursor{T},
    )

    return DatabaseFetcher(Val{orientation}(), preallocated, cursor)
end

fetch_function(::DatabaseFetcher{Val{:columns}}) = fetchintocolumns!
fetch_function(::DatabaseFetcher{Val{:rows}}) = fetchintorows!
fetch_function(::DatabaseFetcher{Val{:array}}) = fetchintoarray!

first_empty(a::Associative) = isempty(first(values(a)))
first_empty(a) = isempty(first(a))

@compat function isempty{O<:Union{Val{:rows}, Val{:array}}, T<:DatabaseInterface, U<:Union{AbstractArray, Associative}}(
        fetcher::DatabaseFetcher{O, T, U}
    )

    isempty(fetcher.preallocated)
end

@compat function isempty{O<:Val{:columns}, T<:DatabaseInterface, U<:Union{AbstractArray, Associative}}(
        fetcher::DatabaseFetcher{O, T, U}
    )

    isempty(fetcher.preallocated) || first_empty(fetcher.preallocated)
end

start(fetcher::DatabaseFetcher) = (fetcher.preallocated, 0)

function next{O, T<:DatabaseInterface, U}(fetcher::DatabaseFetcher{O, T, U}, state)
    preallocated, offset = state
    preallocated::U, new_offset = fetch_function(fetcher)(preallocated, fetcher.cursor, offset)
    return preallocated, (preallocated, new_offset)
end

function done(fetcher::DatabaseFetcher, state)
    state[2] >= length(fetcher.cursor) || isempty(fetcher)
end



end # module
