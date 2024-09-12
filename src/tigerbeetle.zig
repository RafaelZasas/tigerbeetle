const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;

const stdx = @import("stdx.zig");

pub const Account = extern struct {
    id: u128,
    debits_pending: u128,
    debits_posted: u128,
    credits_pending: u128,
    credits_posted: u128,
    /// Opaque third-party identifiers to link this account (many-to-one) to external entities.
    user_data_128: u128,
    user_data_64: u64,
    user_data_32: u32,
    /// Reserved for accounting policy primitives.
    reserved: u32,
    ledger: u32,
    /// A chart of accounts code describing the type of account (e.g. clearing, settlement).
    code: u16,
    flags: AccountFlags,
    timestamp: u64,

    comptime {
        assert(stdx.no_padding(Account));
        assert(@sizeOf(Account) == 128);
        assert(@alignOf(Account) == 16);
    }

    pub fn debits_exceed_credits(self: *const Account, amount: u128) bool {
        return (self.flags.debits_must_not_exceed_credits and
            self.debits_pending + self.debits_posted + amount > self.credits_posted);
    }

    pub fn credits_exceed_debits(self: *const Account, amount: u128) bool {
        return (self.flags.credits_must_not_exceed_debits and
            self.credits_pending + self.credits_posted + amount > self.debits_posted);
    }
};

pub const AccountFlags = packed struct(u16) {
    /// When the .linked flag is specified, it links an event with the next event in the batch, to
    /// create a chain of events, of arbitrary length, which all succeed or fail together. The tail
    /// of a chain is denoted by the first event without this flag. The last event in a batch may
    /// therefore never have the .linked flag set as this would leave a chain open-ended. Multiple
    /// chains or individual events may coexist within a batch to succeed or fail independently.
    /// Events within a chain are executed within order, or are rolled back on error, so that the
    /// effect of each event in the chain is visible to the next, and so that the chain is either
    /// visible or invisible as a unit to subsequent events after the chain. The event that was the
    /// first to break the chain will have a unique error result. Other events in the chain will
    /// have their error result set to .linked_event_failed.
    linked: bool = false,
    debits_must_not_exceed_credits: bool = false,
    credits_must_not_exceed_debits: bool = false,
    history: bool = false,
    imported: bool = false,
    closed: bool = false,
    padding: u10 = 0,

    comptime {
        assert(@sizeOf(AccountFlags) == @sizeOf(u16));
        assert(@bitSizeOf(AccountFlags) == @sizeOf(AccountFlags) * 8);
    }
};

pub const AccountBalance = extern struct {
    debits_pending: u128,
    debits_posted: u128,
    credits_pending: u128,
    credits_posted: u128,
    timestamp: u64,
    reserved: [56]u8 = [_]u8{0} ** 56,

    comptime {
        assert(stdx.no_padding(AccountBalance));
        assert(@sizeOf(AccountBalance) == 128);
        assert(@alignOf(AccountBalance) == 16);
    }
};

pub const Transfer = extern struct {
    id: u128,
    debit_account_id: u128,
    credit_account_id: u128,
    amount: u128,
    /// If this transfer will post or void a pending transfer, the id of that pending transfer.
    pending_id: u128,
    /// Opaque third-party identifiers to link this transfer (many-to-one) to an external entities.
    user_data_128: u128,
    user_data_64: u64,
    user_data_32: u32,
    /// Timeout in seconds for pending transfers to expire automatically
    /// if not manually posted or voided.
    timeout: u32,
    ledger: u32,
    /// A chart of accounts code describing the reason for the transfer (e.g. deposit, settlement).
    code: u16,
    flags: TransferFlags,
    timestamp: u64,

    // Converts the timeout from seconds to ns.
    pub fn timeout_ns(self: *const Transfer) u64 {
        // Casting to u64 to avoid integer overflow:
        return @as(u64, self.timeout) * std.time.ns_per_s;
    }

    comptime {
        assert(stdx.no_padding(Transfer));
        assert(@sizeOf(Transfer) == 128);
        assert(@alignOf(Transfer) == 16);
    }
};

pub const TransferPendingStatus = enum(u8) {
    none = 0,
    pending = 1,
    posted = 2,
    voided = 3,
    expired = 4,

    comptime {
        for (std.enums.values(TransferPendingStatus), 0..) |result, index| {
            assert(@intFromEnum(result) == index);
        }
    }
};

pub const TransferFlags = packed struct(u16) {
    linked: bool = false,
    pending: bool = false,
    post_pending_transfer: bool = false,
    void_pending_transfer: bool = false,
    balancing_debit: bool = false,
    balancing_credit: bool = false,
    closing_debit: bool = false,
    closing_credit: bool = false,
    imported: bool = false,
    padding: u4 = 0,
    denied: TransferDenied = .none,

    comptime {
        assert(@sizeOf(TransferFlags) == @sizeOf(u16));
        assert(@bitSizeOf(TransferFlags) == @sizeOf(TransferFlags) * 8);
    }
};

pub const TransferDenied = enum(u3) {
    none = 0,
    exceeds_debits = 1,
    exceeds_credits = 2,
    debit_account_already_closed = 3,
    credit_account_already_closed = 4,

    comptime {
        for (0..std.enums.values(TransferDenied).len) |index| {
            const result: TransferDenied = @enumFromInt(index);
            assert(@intFromEnum(result) == index);
        }
    }
};

/// Error codes are ordered by descending precedence.
/// When errors do not have an obvious/natural precedence (e.g. "*_must_be_zero"),
/// the ordering matches struct field order.
pub const CreateAccountResult = enum(u32) {
    ok = 0,
    linked_event_failed = 1,
    linked_event_chain_open = 2,

    imported_event_expected = 22,
    imported_event_not_expected = 23,

    timestamp_must_be_zero = 3,

    imported_event_timestamp_out_of_range = 24,
    imported_event_timestamp_must_not_advance = 25,

    reserved_field = 4,
    reserved_flag = 5,

    id_must_not_be_zero = 6,
    id_must_not_be_int_max = 7,

    flags_are_mutually_exclusive = 8,

    debits_pending_must_be_zero = 9,
    debits_posted_must_be_zero = 10,
    credits_pending_must_be_zero = 11,
    credits_posted_must_be_zero = 12,
    ledger_must_not_be_zero = 13,
    code_must_not_be_zero = 14,

    exists_with_different_flags = 15,

    exists_with_different_user_data_128 = 16,
    exists_with_different_user_data_64 = 17,
    exists_with_different_user_data_32 = 18,
    exists_with_different_ledger = 19,
    exists_with_different_code = 20,
    exists = 21,

    imported_event_timestamp_must_not_regress = 26,

    comptime {
        for (0..std.enums.values(CreateAccountResult).len) |index| {
            const result: CreateAccountResult = @enumFromInt(index);
            assert(@intFromEnum(result) == index);
        }
    }
};

/// Error codes are ordered by descending precedence.
/// When errors do not have an obvious/natural precedence (e.g. "*_must_not_be_zero"),
/// the ordering matches struct field order.
pub const CreateTransferResult = enum(u32) {
    ok = 0,
    linked_event_failed = 1,
    linked_event_chain_open = 2,

    //imported_event_expected = 56,
    //imported_event_not_expected = 57,

    timestamp_must_be_zero = 3,

    //imported_event_timestamp_out_of_range = 58,
    //imported_event_timestamp_must_not_advance = 59,

    reserved_flag = 4,

    id_must_not_be_zero = 5,
    id_must_not_be_int_max = 6,

    flags_are_mutually_exclusive = 7,

    debit_account_id_must_not_be_zero = 8,
    debit_account_id_must_not_be_int_max = 9,
    credit_account_id_must_not_be_zero = 10,
    credit_account_id_must_not_be_int_max = 11,
    accounts_must_be_different = 12,

    pending_id_must_be_zero = 13,
    pending_id_must_not_be_zero = 14,
    pending_id_must_not_be_int_max = 15,
    pending_id_must_be_different = 16,
    timeout_reserved_for_pending_transfer = 17,

    //closing_transfer_must_be_pending = 64

    amount_must_not_be_zero = 18,
    ledger_must_not_be_zero = 19,
    code_must_not_be_zero = 20,

    debit_account_not_found = 21,
    credit_account_not_found = 22,

    accounts_must_have_the_same_ledger = 23,
    transfer_must_have_the_same_ledger_as_accounts = 24,

    pending_transfer_not_found = 25,
    pending_transfer_not_pending = 26,

    pending_transfer_has_different_debit_account_id = 27,
    pending_transfer_has_different_credit_account_id = 28,
    pending_transfer_has_different_ledger = 29,
    pending_transfer_has_different_code = 30,

    exceeds_pending_transfer_amount = 31,
    pending_transfer_has_different_amount = 32,

    pending_transfer_already_posted = 33,
    pending_transfer_already_voided = 34,

    pending_transfer_expired = 35,

    exists_with_different_flags = 36,

    exists_with_different_debit_account_id = 37,
    exists_with_different_credit_account_id = 38,
    exists_with_different_amount = 39,
    exists_with_different_pending_id = 40,
    exists_with_different_user_data_128 = 41,
    exists_with_different_user_data_64 = 42,
    exists_with_different_user_data_32 = 43,
    exists_with_different_timeout = 44,
    exists_with_different_code = 45,
    exists = 46,

    //imported_event_timestamp_must_not_regress = 60,
    //imported_event_timestamp_must_postdate_debit_account = 61,
    //imported_event_timestamp_must_postdate_credit_account = 62,
    //imported_event_timeout_must_be_zero = 63,

    overflows_debits_pending = 47,
    overflows_credits_pending = 48,
    overflows_debits_posted = 49,
    overflows_credits_posted = 50,
    overflows_debits = 51,
    overflows_credits = 52,
    overflows_timeout = 53,

    denied_exceeds_credits = 54,
    denied_exceeds_debits = 55,

    // TODO(zig): This enum should be ordered by precedence, but it crashes
    // `EnumSet`, and `@setEvalBranchQuota()` isn't propagating correctly:
    // https://godbolt.org/z/6a45bx6xs
    // error: evaluation exceeded 1000 backwards branches
    // note: use @setEvalBranchQuota() to raise the branch limit from 1000.
    //
    // Workaround:
    // https://github.com/ziglang/zig/blob/66b71273a2555da23f6d706c22e3d85f43fe602b/lib/std/enums.zig#L1278-L1280
    imported_event_expected = 56,
    imported_event_not_expected = 57,
    imported_event_timestamp_out_of_range = 58,
    imported_event_timestamp_must_not_advance = 59,
    imported_event_timestamp_must_not_regress = 60,
    imported_event_timestamp_must_postdate_debit_account = 61,
    imported_event_timestamp_must_postdate_credit_account = 62,
    imported_event_timeout_must_be_zero = 63,

    closing_transfer_must_be_pending = 64,

    denied_debit_account_already_closed = 65,
    denied_credit_account_already_closed = 66,

    comptime {
        for (0..std.enums.values(CreateTransferResult).len) |index| {
            const result: CreateTransferResult = @enumFromInt(index);
            assert(@intFromEnum(result) == index);
        }
    }
};

pub const CreateAccountsResult = extern struct {
    index: u32,
    result: CreateAccountResult,

    comptime {
        assert(@sizeOf(CreateAccountsResult) == 8);
        assert(stdx.no_padding(CreateAccountsResult));
    }
};

pub const CreateTransfersResult = extern struct {
    index: u32,
    result: CreateTransferResult,

    comptime {
        assert(@sizeOf(CreateTransfersResult) == 8);
        assert(stdx.no_padding(CreateTransfersResult));
    }
};

pub const QueryFilter = extern struct {
    /// Query by the `user_data_128` index.
    /// Use zero for no filter.
    user_data_128: u128,
    /// Query by the `user_data_64` index.
    /// Use zero for no filter.
    user_data_64: u64,
    /// Query by the `user_data_32` index.
    /// Use zero for no filter.
    user_data_32: u32,
    /// Query by the `ledger` index.
    /// Use zero for no filter.
    ledger: u32,
    /// Query by the `code` index.
    /// Use zero for no filter.
    code: u16,
    reserved: [6]u8 = [_]u8{0} ** 6,
    /// The initial timestamp (inclusive).
    /// Use zero for no filter.
    timestamp_min: u64,
    /// The final timestamp (inclusive).
    /// Use zero for no filter.
    timestamp_max: u64,
    /// Maximum number of results that can be returned by this query.
    /// Must be greater than zero.
    limit: u32,
    /// Query flags.
    flags: QueryFilterFlags,

    comptime {
        assert(@sizeOf(QueryFilter) == 64);
        assert(stdx.no_padding(QueryFilter));
    }
};

pub const QueryFilterFlags = packed struct(u32) {
    /// Whether the results are sorted by timestamp in chronological or reverse-chronological order.
    reversed: bool,
    padding: u31 = 0,

    comptime {
        assert(@sizeOf(QueryFilterFlags) == @sizeOf(u32));
        assert(@bitSizeOf(QueryFilterFlags) == @sizeOf(QueryFilterFlags) * 8);
    }
};

/// Filter used in both `get_account_transfer` and `get_account_balances`.
pub const AccountFilter = extern struct {
    /// The account id.
    account_id: u128,
    /// Filter by the `user_data_128` index.
    /// Use zero for no filter.
    user_data_128: u128,
    /// Filter by the `user_data_64` index.
    /// Use zero for no filter.
    user_data_64: u64,
    /// Filter by the `user_data_32` index.
    /// Use zero for no filter.
    user_data_32: u32,
    /// Query by the `code` index.
    /// Use zero for no filter.
    code: u16,

    reserved: [58]u8 = [_]u8{0} ** 58,
    /// The initial timestamp (inclusive).
    /// Use zero for no filter.
    timestamp_min: u64,
    /// The final timestamp (inclusive).
    /// Use zero for no filter.
    timestamp_max: u64,
    /// Maximum number of results that can be returned by this query.
    /// Must be greater than zero.
    limit: u32,
    /// Query flags.
    flags: AccountFilterFlags,

    comptime {
        assert(@sizeOf(AccountFilter) == 128);
        assert(stdx.no_padding(AccountFilter));
    }
};

pub const AccountFilterFlags = packed struct(u32) {
    /// Whether to include results where `debit_account_id` matches.
    debits: bool,
    /// Whether to include results where `credit_account_id` matches.
    credits: bool,
    /// Whether the results are sorted by timestamp in chronological or reverse-chronological order.
    reversed: bool,
    padding: u29 = 0,

    comptime {
        assert(@sizeOf(AccountFilterFlags) == @sizeOf(u32));
        assert(@bitSizeOf(AccountFilterFlags) == @sizeOf(AccountFilterFlags) * 8);
    }
};

comptime {
    const target = builtin.target;

    if (target.os.tag != .linux and !target.isDarwin() and target.os.tag != .windows) {
        @compileError("linux, windows or macos is required for io");
    }

    // We require little-endian architectures everywhere for efficient network deserialization:
    if (target.cpu.arch.endian() != .little) {
        @compileError("big-endian systems not supported");
    }

    switch (builtin.mode) {
        .Debug, .ReleaseSafe => {},
        .ReleaseFast, .ReleaseSmall => @compileError("safety checks are required for correctness"),
    }
}
