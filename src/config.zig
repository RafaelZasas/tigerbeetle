//! Raw configuration values.
//!
//! Code which needs these values should use `constants.zig` instead.
//! Configuration values are set from a combination of:
//! - default values
//! - `root.tigerbeetle_config`
//! - `@import("tigerbeetle_options")`

const builtin = @import("builtin");
const std = @import("std");

const root = @import("root");
// Allow setting build-time config either via `build.zig` `Options`, or via a struct in the root file.
const build_options =
    if (@hasDecl(root, "vsr_options")) root.vsr_options else @import("vsr_options");

const vsr = @import("vsr.zig");
const sector_size = @import("constants.zig").sector_size;

pub const Config = struct {
    pub const Cluster = ConfigCluster;
    pub const Process = ConfigProcess;

    cluster: ConfigCluster,
    process: ConfigProcess,
};

/// Configurations which are tunable per-replica (or per-client).
/// - Replica configs need not equal each other.
/// - Client configs need not equal each other.
/// - Client configs need not equal replica configs.
/// - Replica configs can change between restarts.
///
/// Fields are documented within constants.zig.
const ConfigProcess = struct {
    log_level: std.log.Level = .info,
    tracer_backend: TracerBackend = .none,
    hash_log_mode: HashLogMode = .none,
    verify: bool,
    port: u16 = 3001,
    address: []const u8 = "127.0.0.1",
    memory_size_max_default: u64 = 1024 * 1024 * 1024,
    cache_accounts_max: usize,
    cache_transfers_max: usize,
    cache_transfers_posted_max: usize,
    client_request_queue_max: usize = 32,
    lsm_manifest_node_size: usize = 16 * 1024,
    connection_delay_min_ms: u64 = 50,
    connection_delay_max_ms: u64 = 1000,
    tcp_backlog: u31 = 64,
    tcp_rcvbuf: c_int = 4 * 1024 * 1024,
    tcp_keepalive: bool = true,
    tcp_keepidle: c_int = 5,
    tcp_keepintvl: c_int = 4,
    tcp_keepcnt: c_int = 3,
    tcp_nodelay: bool = true,
    direct_io: bool,
    direct_io_required: bool,
    journal_iops_read_max: usize = 8,
    journal_iops_write_max: usize = 8,
    tick_ms: u63 = 10,
    rtt_ms: u64 = 300,
    rtt_multiple: u8 = 2,
    backoff_min_ms: u64 = 100,
    backoff_max_ms: u64 = 10000,
    clock_offset_tolerance_max_ms: u64 = 10000,
    clock_epoch_max_ms: u64 = 60000,
    clock_synchronization_window_min_ms: u64 = 2000,
    clock_synchronization_window_max_ms: u64 = 20000,
};

/// Configurations which are tunable per-cluster.
/// - All replicas within a cluster must have the same configuration.
/// - Replicas must reuse the same configuration when the binary is upgraded — they do not change
///   over the cluster lifetime.
/// - The storage formats generated by different ConfigClusters are incompatible.
///
/// Fields are documented within constants.zig.
const ConfigCluster = struct {
    cache_line_size: comptime_int = 64,
    clients_max: usize,
    pipeline_prepare_queue_max: usize = 8,
    view_change_headers_suffix_max: usize = 8,
    view_change_headers_hook_max: usize = 1,
    quorum_replication_max: u8 = 3,
    journal_slot_count: usize = 1024,
    message_size_max: usize = 1 * 1024 * 1024,
    superblock_copies: comptime_int = 4,
    storage_size_max: u64 = 16 * 1024 * 1024 * 1024 * 1024,
    block_size: comptime_int = 64 * 1024,
    lsm_levels: u7 = 7,
    lsm_growth_factor: u32 = 8,
    lsm_batch_multiple: comptime_int = 64,
    lsm_snapshots_max: usize = 32,
    lsm_value_to_key_layout_ratio_min: comptime_int = 16,

    /// The WAL requires at least two sectors of redundant headers — otherwise we could lose them all to
    /// a single torn write. A replica needs at least one valid redundant header to determine an
    /// (untrusted) maximum op in recover_torn_prepare(), without which it cannot truncate a torn
    /// prepare.
    pub const journal_slot_count_min = 2 * @divExact(sector_size, @sizeOf(vsr.Header));

    pub const clients_max_min = 1;

    /// The smallest possible message_size_max (for use in the simulator to improve performance).
    /// The message body must have room for pipeline_prepare_queue_max headers in the DVC.
    pub fn message_size_max_min(clients_max: usize) usize {
        return std.math.max(
            sector_size,
            std.mem.alignForward(
                @sizeOf(vsr.Header) + clients_max * @sizeOf(vsr.Header),
                sector_size,
            ),
        );
    }
};

pub const ConfigBase = enum {
    production,
    development,
    test_min,
    default,
};

pub const TracerBackend = enum {
    none,
    // Writes to a file (./tracer.json) which can be uploaded to https://ui.perfetto.dev/
    perfetto,
    // Sends data to https://github.com/wolfpld/tracy.
    tracy,
};

pub const HashLogMode = enum {
    none,
    create,
    check,
};

pub const configs = struct {
    /// A good default config for production.
    pub const default_production = Config{
        .process = .{
            .direct_io = true,
            .direct_io_required = true,
            .cache_accounts_max = 1024 * 1024,
            .cache_transfers_max = 0,
            .cache_transfers_posted_max = 256 * 1024,
            .verify = false,
        },
        .cluster = .{
            .clients_max = 32,
        },
    };

    /// A good default config for local development.
    /// (For production, use default_production instead.)
    /// The cluster-config is compatible with the default production config.
    pub const default_development = Config{
        .process = .{
            .direct_io = true,
            .direct_io_required = false,
            .cache_accounts_max = 1024 * 1024,
            .cache_transfers_max = 0,
            .cache_transfers_posted_max = 256 * 1024,
            .verify = true,
        },
        .cluster = default_production.cluster,
    };

    /// Minimal test configuration — small WAL, small grid block size, etc.
    /// Not suitable for production, but good for testing code that would be otherwise hard to reach.
    pub const test_min = Config{
        .process = .{
            .direct_io = false,
            .direct_io_required = false,
            .cache_accounts_max = 2048,
            .cache_transfers_max = 0,
            .cache_transfers_posted_max = 2048,
            .verify = true,
        },
        .cluster = .{
            .clients_max = 4 + 3,
            .pipeline_prepare_queue_max = 4,
            .view_change_headers_suffix_max = 4,
            .journal_slot_count = Config.Cluster.journal_slot_count_min,
            .message_size_max = Config.Cluster.message_size_max_min(4),
            .storage_size_max = 4 * 1024 * 1024 * 1024,

            .block_size = sector_size,
            .lsm_batch_multiple = 4,
            .lsm_growth_factor = 4,
        },
    };

    const default = if (@hasDecl(root, "tigerbeetle_config"))
        root.tigerbeetle_config
    else if (builtin.is_test)
        test_min
    else
        default_development;

    pub const current = current: {
        var base = if (@hasDecl(root, "decode_events"))
            // TODO(DJ) This is a hack to work around the absense of tigerbeetle_build_options.
            // This should be removed once the node client is built using `zig build`.
            default_development
        else switch (build_options.config_base) {
            .default => default,
            .production => default_production,
            .development => default_development,
            .test_min => test_min,
        };

        // TODO Use additional build options to overwrite other fields.
        base.process.tracer_backend = if (@hasDecl(root, "tracer_backend"))
            // TODO(jamii)
            // This branch is a hack used to work around the absence of tigerbeetle_build_options.
            // This should be removed once the node client is built using `zig build`.
            root.tracer_backend
        else
            // Zig's `addOptions` reuses the type, but redeclares it — identical structurally,
            // but a different type from a nominal typing perspective.
            @intToEnum(TracerBackend, @enumToInt(build_options.tracer_backend));

        base.process.hash_log_mode = if (@hasDecl(root, "decode_events"))
            // TODO(DJ) This is a hack to work around the absense of tigerbeetle_build_options.
            // This should be removed once the node client is built using `zig build`.
            .none
        else
            @intToEnum(HashLogMode, @enumToInt(build_options.hash_log_mode));

        break :current base;
    };
};
