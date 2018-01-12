local ffi = require('ffi')

--
-- There are 3 error types:
-- * lua error - it is created on assertions, syntax errors,
--   luajit OOM etc. It has attributes type = 'LuajitError' and
--   optional message;
-- * box_error - it is created on tarantool errors: client error,
--   oom error, socket error etc. It has type = one of tarantool
--   error types, trace (file, line), message;
-- * vshard_error - it is created on sharding errors like
--   replicaset unavailability, master absense etc. It has type =
--   'ShardingError', one of codes below and optional
--   message.
--
local function lua_error(msg)
    return { type = 'LuajitError', message = msg }
end

local function box_error(original_error)
    return original_error:unpack()
end

local function vshard_error(code, args, msg)
    local ret = { type = 'ShardingError', code = code, message = msg }
    for k, v in pairs(args) do
        ret[k] = v
    end
    return ret
end

--
-- Convert error object from pcall to lua, box or vshard error
-- object.
--
local function make_error(e)
   if type(e) == 'table' then
       -- Custom error object, return as is
       return e
   elseif type(e) == 'cdata' and ffi.istype('struct error', e) then
       -- box.error, return unpacked
       return box_error(e)
   else
       -- Lua error, return wrapped
       return lua_error(tostring(e))
   end
end

local error_code = {
    -- Error codes. Some of them are used for alerts too.
    WRONG_BUCKET = 1,
    NON_MASTER = 2,
    BUCKET_ALREADY_EXISTS = 3,
    NO_SUCH_REPLICASET = 4,
    MOVE_TO_SELF = 5,
    MISSING_MASTER = 6,
    TRANSFER_IS_IN_PROGRESS = 7,
    REPLICASET_IS_UNREACHABLE = 8,
    NO_ROUTE_TO_BUCKET = 9,
    NON_EMPTY = 10,

    -- Alert codes.
    UNREACHABLE_MASTER = 11,
    OUT_OF_SYNC = 12,
    HIGH_REPLICATION_LAG = 13,
    REPLICA_IS_DOWN = 14,
    LOW_REDUNDANCY = 15,
    INVALID_REBALANCING = 16,
}

local error_message_template = {
    [error_code.MISSING_MASTER] = {
         name = 'MISSING_MASTER',
         msg = 'Master is not configured for this replicaset'
    },
    [error_code.UNREACHABLE_MASTER] = {
        name = 'UNREACHABLE_MASTER',
        msg = 'Master is unreachable: %s'
    },
    [error_code.OUT_OF_SYNC] = {
        name = 'OUT_OF_SYNC',
        msg = 'Replica is out of sync'
    },
    [error_code.HIGH_REPLICATION_LAG] = {
        name = 'HIGH_REPLICATION_LAG',
        msg = 'High replication lag: %f'
    },
    [error_code.REPLICA_IS_DOWN] = {
        name = 'REPLICA_IS_DOWN',
        msg = "Replica %s isn't active"
    },
    [error_code.REPLICASET_IS_UNREACHABLE] = {
        name = 'REPLICASET_IS_UNREACHABLE',
        msg = 'There is no active replicas'
    },
    [error_code.LOW_REDUNDANCY] = {
        name = 'LOW_REDUNDANCY',
        msg = 'Only one replica is active'
    },
    [error_code.INVALID_REBALANCING] = {
        name = 'INVALID_REBALANCING',
        msg = 'Sending and receiving buckets at same time is not allowed'
    },
}

local function make_alert(code, ...)
    local format = error_message_template[code]
    assert(format)
    local r = {format.name, string.format(format.msg, ...)}
    return setmetatable(r, { __serialize = 'seq' })
end

return {
    code = error_code,
    lua = lua_error,
    box = box_error,
    vshard = vshard_error,
    make = make_error,
    alert = make_alert,
}
