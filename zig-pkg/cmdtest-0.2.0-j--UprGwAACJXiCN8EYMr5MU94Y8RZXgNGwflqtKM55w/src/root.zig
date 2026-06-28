const std = @import("std");
const testing = std.testing;
const process = std.process;
const Environ = std.process.Environ;

/// Options for `run` controlling I/O, allocator, and output limits.
pub const RunOptions = struct {
    /// Argument vector passed to the child process.
    /// The first element is the executable name or path.
    ///
    /// For examples:
    ///
    /// [_][]const u8 {"echo", "hello"}
    /// [_][]const u8 {"/bin/echo", "hello"}
    /// [_][]const u8 {"./zig-out/bin/echo", "hello"}
    ///
    argv: []const []const u8,

    /// Allocator used for any allocations performed by `run` and for
    /// capturing stdout/stderr. Defaults to `std.testing.allocator`, which
    /// enables leak detection and is good for tests to ensure proper
    /// memory management.
    allocator: std.mem.Allocator = testing.allocator,

    /// Optional bytes to write into the child's stdin. When provided the
    /// child's stdin will be a pipe and the bytes will be written then the
    /// write-end closed to signal EOF. If null the child's stdin is ignored.
    stdin: ?[]const u8 = null,

    /// Maximum number of bytes to write into the child's stdin.
    /// Defaults to 64 KiB to avoid excessive memory usage for typical CLI test cases.
    /// If the provided `stdin` slice is larger, it will be truncated to this size.
    max_stdin_bytes: usize = 64 * 1024,

    /// Maximum number of bytes to capture from stdout/stderr. Output beyond
    /// this limit will be discarded.
    max_output_bytes: usize = 64 * 1024,

    /// Optional working directory for the child process.
    /// When non-null the child will be started with this path as its current working directory.
    /// When null, the child inherits the parent's working directory.
    cwd: ?[]const u8 = null,

    /// Optional environment map to use for the child process. If provided
    /// the child will use this `Environ.Map` instead of inheriting the parent's
    /// environment. The caller must ensure the provided `Environ.Map` remains valid
    /// and unmodified for the entire duration of the child process execution.
    env_map: ?*const Environ.Map = null,
};

/// Result returned by `run` with exit info and captured output.
pub const RunResult = struct {
    /// Exit code returned by the child process.
    /// If the process exited normally, this is the exit code.
    /// If terminated by signal or other reason, this is 0.
    code: u8,

    /// Process termination reason, such as exit or signal, from `Child.wait()`.
    term: process.Child.Term,

    /// Captured stdout slice. If the child's output exceeds `max_output_bytes`, this will be truncated.
    stdout: []const u8,

    /// Captured stderr bytes. If the child's output exceeds `max_output_bytes`, this will be truncated.
    stderr: []const u8,

    /// Allocator used for the captured buffers.
    allocator: std.mem.Allocator,

    /// Frees the captured output buffers.
    /// Must be called to avoid memory leaks after using `RunResult`.
    pub fn deinit(self: *RunResult) void {
        self.allocator.free(self.stdout);
        self.allocator.free(self.stderr);
    }
};

/// Run an executable synchronously and capture its output.
///
/// Spawns the child process, collects stdout and stderr up to `max_output_bytes`,
/// waits for termination, and returns a `RunResult` with captured output and termination info.
/// Returns an error on spawn, I/O, or wait failure.
/// The caller must call `RunResult.deinit` to free captured output buffers.
pub fn run(io: std.Io, options: RunOptions) !RunResult {
    // Spawn the child process with optional cwd and env_map
    var child = try process.spawn(io, .{
        .argv = options.argv,
        .cwd = if (options.cwd) |cwd_path| .{ .path = cwd_path } else .inherit,
        .environ_map = options.env_map,
        .stdin = if (options.stdin != null) .pipe else .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
    });
    defer child.kill(io);

    // If stdin content was provided, write it to the child's stdin pipe and
    // close the pipe so the child sees EOF.
    if (options.stdin) |stdin_bytes| {
        if (child.stdin) |stdin_file| {
            // Determine how many bytes we will actually write (truncate if needed)
            const write_len = if (@as(usize, stdin_bytes.len) < options.max_stdin_bytes)
                @as(usize, stdin_bytes.len)
            else
                options.max_stdin_bytes;

            var buf: [1024]u8 = undefined;
            var stdin_writer = stdin_file.writer(io, &buf);
            try stdin_writer.interface.writeAll(stdin_bytes[0..write_len]);
            try stdin_writer.interface.flush();
            stdin_file.close(io);

            // Mark as closed to avoid double-close
            child.stdin = null;
        }
    }

    // Collect stdout and stderr using MultiReader
    var multi_reader_buffer: std.Io.File.MultiReader.Buffer(2) = undefined;
    var multi_reader: std.Io.File.MultiReader = undefined;
    multi_reader.init(options.allocator, io, multi_reader_buffer.toStreams(), &.{
        child.stdout.?,
        child.stderr.?,
    });
    defer multi_reader.deinit();

    const stdout_reader = multi_reader.reader(0);
    const stderr_reader = multi_reader.reader(1);

    const output_limit = std.Io.Limit.limited(options.max_output_bytes);

    // Fill the multi reader until EOF
    while (multi_reader.fill(1, .none)) |_| {
        // Check output limits after each fill
        if (output_limit.toInt()) |limit| {
            if (stdout_reader.buffered().len > limit or stderr_reader.buffered().len > limit) {
                return error.OutputTooLong;
            }
        }
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => |e| return e,
    }

    try multi_reader.checkAnyError();

    const term = try child.wait(io);

    // Convert term to exit code
    const code = switch (term) {
        .exited => |exit_code| exit_code,
        .signal => 0,
        .stopped => 0,
        .unknown => 0,
    };

    const stdout_slice = try multi_reader.toOwnedSlice(0);
    errdefer options.allocator.free(stdout_slice);

    const stderr_slice = try multi_reader.toOwnedSlice(1);
    errdefer options.allocator.free(stderr_slice);

    return RunResult{
        .code = code,
        .term = term,
        .stdout = stdout_slice,
        .stderr = stderr_slice,
        .allocator = options.allocator,
    };
}

pub const Error = error{
    OutputTooLong,
};

/// Options for `spawn` controlling the child process environment.
pub const SpawnOptions = struct {
    argv: []const []const u8,
    allocator: std.mem.Allocator = testing.allocator,
    cwd: ?[]const u8 = null,
    env_map: ?*const Environ.Map = null,
};

/// Manages a long-running, interactive child process for testing.
pub const InteractiveProcess = struct {
    const Self = @This();

    child: process.Child,
    io: std.Io,
    stdout_buffer: [1024]u8 = undefined,
    stdin_buffer: [1024]u8 = undefined,
    stderr_buffer: [1024]u8 = undefined,

    /// Cleans up resources and ensures the child process is terminated.
    /// This should always be called, typically with `defer`.
    pub fn deinit(self: *Self) void {
        self.child.kill(self.io);
    }

    pub const WriteError = error{
        // This means process already exited or child.stdin is closed
        ProcessExited,
        // This means something wrong when writing to stdin
        WriteFailed,
    };

    pub const ReadStdoutError = error{
        // This means process already exited
        ProcessExited,
        // This means something wrong when reading from stdout
        ReadFailed,
    };

    /// Writes bytes to the child process's stdin.
    ///
    /// This method attempts to write all bytes and flush the underlying pipe.
    /// If the child's stdin is not available (closed or process exited) this
    /// returns `error.ProcessExited`. Other I/O failures return `error.WriteFailed`.
    ///
    /// Notes:
    /// - Writing to a child's stdin only writes into the OS pipe buffer. It does
    ///   not guarantee the child will read or consume those bytes. For example,
    ///   a process that intentionally ignores stdin (or never reads from it) may
    ///   still make `write` succeed because the bytes are buffered by the OS.
    /// - Short-lived commands may introduce a timing/race condition: a command
    ///   might exit quickly around the same time as a write attempt. Depending
    ///   on timing, `write` may succeed because the write occurred before the
    ///   kernel noticed the process exit (or due to buffering), or it may return
    ///   `error.ProcessExited`. As a result, tests asserting a deterministic
    ///   `error.ProcessExited` for short-lived commands can be flaky and may
    ///   need to be skipped for reliability.
    pub fn write(self: *Self, bytes: []const u8) WriteError!void {
        const stdin_file = self.child.stdin orelse return error.ProcessExited;
        var stdin_writer = stdin_file.writer(self.io, &self.stdin_buffer);
        var stdin = &stdin_writer.interface;
        stdin.writeAll(bytes) catch return error.WriteFailed;
        stdin.flush() catch return error.WriteFailed;
    }

    /// Reads from the child's stdout until a newline is found or the buffer is full.
    /// The returned slice does not include the newline character.
    pub fn readLineFromStdout(self: *Self) ReadStdoutError![]const u8 {
        const stdout_file = self.child.stdout orelse return error.ProcessExited;
        var stdout_reader = stdout_file.reader(self.io, &self.stdout_buffer);
        var stdout = &stdout_reader.interface;
        const line = stdout.takeDelimiter('\n') catch return error.ReadFailed;
        // Handle potential CR on Windows if the child outputs CRLF
        const trimmed = std.mem.trimEnd(u8, line.?, "\r");
        return trimmed;
    }

    /// Reads from the child's stderr until a newline is found.
    pub fn readLineFromStderr(self: *Self) ![]const u8 {
        const stderr_file = self.child.stderr orelse return error.MissingStderr;
        var stderr_reader = stderr_file.reader(self.io, &self.stderr_buffer);
        var stderr = &stderr_reader.interface;
        const line = try stderr.takeDelimiter('\n') orelse return error.EmptyLine;
        // Handle potential CR on Windows if the child outputs CRLF
        const trimmed = std.mem.trimEnd(u8, line, "\r");
        return trimmed;
    }

    // TODO: add expectStdout
    // TODO: add expectStderr

    pub fn expectStdout(self: *Self, expected: []const u8) !void {
        var stderr_file = std.Io.File.stdout();
        var stderr_writer = stderr_file.writer(self.io, &self.stderr_buffer);
        var stderr = &stderr_writer.interface;

        const actual = self.readLineFromStdout() catch |err| {
            try stderr.print("\n\n--- Test Expectation Failed ---\n", .{});
            try stderr.print("Expected to read from stdout:\n{s}\n\n", .{expected});
            try stderr.print("But the read operation failed with error: {any}\n", .{err});
            try stderr.print("---------------------------------\n\n", .{});
            try stderr.flush();
            return err;
        };

        std.testing.expectEqualStrings(expected, actual) catch |err| {
            try stderr.print("\n\n--- HELLO ---\n", .{});
            return err;
        };
    }
};

/// Spawns an executable for interactive testing.
///
/// Returns an `InteractiveProcess` object to manage the child process's
/// lifecycle and I/O. The caller is responsible for calling `deinit()`
/// on the returned object to ensure cleanup.
pub fn spawn(io: std.Io, options: SpawnOptions) !InteractiveProcess {
    const child = try process.spawn(io, .{
        .argv = options.argv,
        .cwd = if (options.cwd) |cwd_path| .{ .path = cwd_path } else .inherit,
        .environ_map = options.env_map,
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .pipe,
    });

    return InteractiveProcess{ .child = child, .io = io };
}
