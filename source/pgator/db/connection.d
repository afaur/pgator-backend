// Written in D programming language
/**
*   Medium sized wrapper around PostgreSQL connection. 
*   
*   Copyright: © 2014 DSoftOut
*   License: Subject to the terms of the MIT license, as written in the included LICENSE file.
*   Authors: NCrashed <ncrashed@gmail.com>
*/
module pgator.db.connection;

import pgator.db.pq.api;
import std.container;
import std.datetime;
import std.range;

/**
*    The exception is thrown when connection attempt to SQL server is failed due some reason.
*/
class ConnectException : Exception
{
    string server;
    
    @safe pure nothrow this(string server, string msg, string file = __FILE__, size_t line = __LINE__)
    {
        this.server = server;
        super("Failed to connect to SQL server "~server~", reason: " ~ msg, file, line); 
    }
}

/**
*   The exception is thrown when $(B reconnect) method is called, but there wasn't any call of
*   $(B connect) method to grab connection string from.
*/
class ReconnectException : ConnectException
{
    @safe pure nothrow this(string server, string file = __FILE__, size_t line = __LINE__)
    {
        super(server, "Connection reconnect method is called, but there wasn't any call of "
                      "connect method to grab connection string from", file, line);
    }
}

/**
*   The exception is thrown when query is failed due some reason.
*/
class QueryException : Exception
{
    @safe pure nothrow this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super("Query to SQL server is failed, reason: " ~ msg, file, line); 
    }
}

/**
*   Describes result of connection status polling.
*/
enum ConnectionStatus
{
    /// Connection is in progress
    Pending,
    /// Connection is finished with error
    Error,
    /// Connection is finished successfully
    Finished
}

/**
*   Describes result of quering status polling.
*/
enum QueringStatus
{
    /// Quering is in progress
    Pending,
    /// SQL server returned an error
    Error,
    /// SQL server returned normal result
    Finished
}

/**
*   Representing server configuration for
*   displaying dates and converting ambitious values.
*/
struct DateFormat
{
    /**
    *   Representing output format.
    */
    enum StringFormat
    {
        ISO,
        Postgres,
        SQL,
        German,
        Unknown
    }
    
    static StringFormat stringFormatIn(string val)
    {
        foreach(s; __traits(allMembers, StringFormat))
        {
            if(val == s) return mixin("StringFormat."~s);
        }
        return StringFormat.Unknown;
    }
    
    /**
    *   Representing behavior for ambitious values.
    */
    enum OrderFormat
    {
        /// Day Month Year
        DMY, 
        /// Month Day Year
        MDY,
        /// Year Month Day
        YMD,
        /// Unsupported by the bindings
        Unknown
    }
    
    static OrderFormat orderFormatIn(string val)
    {
        foreach(s; __traits(allMembers, OrderFormat))
        {
            if(val == s) return mixin("OrderFormat."~s);
        }
        return OrderFormat.Unknown;
    }
    
    /// Current output format
    StringFormat stringFormat;
    /// Current order format
    OrderFormat  orderFormat;
    
    this(string stringFmt, string orderFmt)
    {
        stringFormat = stringFormatIn(stringFmt);
        orderFormat = orderFormatIn(orderFmt);
    }
}

/**
*   Enum describes two possible server configuration for timestamp format.
*/
enum TimestampFormat
{
    /// Server uses long (usecs) to encode time 
    Int64,
    /// Server uses double (seconds) to encode time
    Float8
}

/**
*    Handles a single connection to a SQL server.
*/
interface IConnection
{
    synchronized:
    
    /**
    *    Tries to establish connection with a SQL server described
    *    in $(B connString). 
    *
    *    Throws: ConnectException
    */
    void connect(string connString);
    
    /**
    *   Tries to establish connection with a SQL server described
    *   in previous call of $(B connect). 
    *
    *   Should throw ReconnectException if method cannot get stored
    *   connection string (the $(B connect) method wasn't called).
    *
    *   Throws: ConnectException, ReconnectException
    */
    void reconnect();
    
    /**
    *   Returns current status of connection.
    */
    ConnectionStatus pollConnectionStatus() nothrow;
    
    /**
    *   If connection process is ended with error state, then
    *   throws ConnectException, else do nothing.
    *
    *   Throws: ConnectException
    */    
    void pollConnectionException();
    
    /**
    *   Initializes querying process in non-blocking manner.
    *   Throws: QueryException
    */
    void postQuery(string com, string[] params = []);
    
    /**
    *   Returns quering status of connection.
    */
    QueringStatus pollQueringStatus() nothrow;
    
    /**
    *   If quering process is ended with error state, then
    *   throws QueryException, else do nothing.
    *
    *   Throws: QueryException
    */
    void pollQueryException();
    
    /**
    *   Returns query result, if $(B pollQueringStatus) shows that
    *   query is processed without errors, else blocks the caller
    *   until the answer is arrived.
    */
    InputRange!(shared IPGresult) getQueryResult();
    
    /**
    *    Closes connection to the SQL server instantly.    
    *    
    *    Also should interrupt connections in progress.
    *
    *    Calls $(B callback) when closed.
    */
    void disconnect() nothrow;
    
    /**
    *   Returns SQL server name (domain) the connection is desired to connect to.
    *   If connection isn't ever established (or tried) the method returns empty string.
    */
    string server() nothrow const @property;
    
    /**
    *   Returns current date output format and ambitious values converting behavior.
    *   Throws: QueryException
    */
    DateFormat dateFormat() @property;
    
    /**
    *   Returns actual time stamp representation format used in server.
    *
    *   Note: This property tells particular HAVE_INT64_TIMESTAMP version flag that is used
    *         by remote server.
    *
    *   Note: Will fallback to Int64 value if server protocol doesn't support acquiring of
    *         'integer_datetimes' parameter.
    */
    TimestampFormat timestampFormat() @property;
    
    /**
    *   Returns server time zone. This value is important to handle 
    *   time stamps with time zone specified as libpq doesn't send
    *   the information with time stamp.
    *
    *   Note: Will fallback to UTC value if server protocol doesn't support acquiring of
    *         'TimeZone' parameter or server returns invalid time zone name.
    */
    immutable(TimeZone) timeZone() @property;
    
    /**
    *   Sending senseless query to the server to check if the connection is
    *   actually alive (e.g. nothing can detect fail after postgresql restart but
    *   query).
    */
    bool testAlive() nothrow;
    
    /**
    *   Blocking wrapper to one-command query execution.
    */
    final InputRange!(shared IPGresult) execQuery(string com, string[] params = [])
    {
        postQuery(com, params);
        
        QueringStatus status;
        do
        {
            status = pollQueringStatus;
            if(status == QueringStatus.Error) pollQueryException;
        } 
        while(status != QueringStatus.Finished);
        
        return getQueryResult;
    }
    
    /**
    *   Returns true if the connection stores info/warning/error messages.
    */
    bool hasRaisedMsgs();
    
    /**
    *   Returns all saved info/warning/error messages from the connection.
    */
    InputRange!string raisedMsgs();
    
    /**
    *   Cleaning inner buffer for info/warning/error messages.
    */
    void clearRaisedMsgs();
}

/**
*   Interface that produces connection objects. Used
*   to isolate connection pool from particular connection
*   realization.
*/
interface IConnectionProvider
{
    /**
    *   Allocates new connection shared across threads.
    */
    synchronized shared(IConnection) allocate();
}