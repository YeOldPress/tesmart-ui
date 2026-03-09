// native.zig — OS-native file dialogs and icon file management
const std = @import("std");
const builtin = @import("builtin");

// Use libc's popen/fgets/pclose (already linked via raylib)
extern "c" fn popen(command: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern "c" fn pclose(stream: *anyopaque) c_int;
extern "c" fn fgets(buf: [*]u8, size: c_int, stream: *anyopaque) ?[*]u8;

/// Open the OS-native file picker for image files.
/// Returns the chosen path length written into `out`, or 0 if cancelled.
pub fn openImageDialog(out: []u8) usize {
    const cmd: [*:0]const u8 = switch (builtin.os.tag) {
        .macos => "osascript -e 'POSIX path of (choose file of type {\"public.image\"} with prompt \"Select an icon image\")' 2>/dev/null",
        .linux => "zenity --file-selection --file-filter='Images | *.png *.jpg *.jpeg *.gif *.bmp *.svg' 2>/dev/null",
        .windows => "powershell -NoProfile -Command \"Add-Type -AssemblyName System.Windows.Forms; $f = New-Object System.Windows.Forms.OpenFileDialog; $f.Filter = 'Images|*.png;*.jpg;*.jpeg;*.bmp;*.gif'; if($f.ShowDialog() -eq 'OK'){Write-Host $f.FileName}\" 2>nul",
        else => return 0,
    };

    const pipe = popen(cmd, "r") orelse return 0;
    defer _ = pclose(pipe);

    var line_buf: [1024]u8 = undefined;
    const result = fgets(&line_buf, @intCast(line_buf.len), pipe) orelse return 0;
    _ = result;

    // Find length (stop at newline or null)
    var len: usize = 0;
    while (len < line_buf.len and line_buf[len] != 0 and line_buf[len] != '\n' and line_buf[len] != '\r') : (len += 1) {}

    if (len == 0) return 0;
    const n = @min(len, out.len);
    @memcpy(out[0..n], line_buf[0..n]);
    return n;
}

/// Copy `src_path` into `dest_dir`, keeping the original filename.
/// Returns the filename length written into `name_out`.
pub fn copyIconToDir(src_path: []const u8, dest_dir: []const u8, name_out: []u8) !usize {
    // Extract filename from path
    var last_sep: usize = 0;
    for (src_path, 0..) |c, i| {
        if (c == '/' or c == '\\') last_sep = i + 1;
    }
    const filename = src_path[last_sep..];
    if (filename.len == 0) return error.EmptyFilename;

    // Build destination path: dest_dir/filename
    var dest_path: [1024]u8 = undefined;
    if (dest_dir.len + 1 + filename.len > dest_path.len) return error.PathTooLong;
    @memcpy(dest_path[0..dest_dir.len], dest_dir);
    dest_path[dest_dir.len] = '/';
    @memcpy(dest_path[dest_dir.len + 1 ..][0..filename.len], filename);
    const dest_len = dest_dir.len + 1 + filename.len;

    // Read source file
    const src_file = try std.fs.cwd().openFile(src_path, .{});
    defer src_file.close();
    const stat = try src_file.stat();
    if (stat.size > 10 * 1024 * 1024) return error.FileTooLarge; // 10MB max

    var read_buf: [10 * 1024 * 1024]u8 = undefined;
    const bytes_read = try src_file.readAll(read_buf[0..@min(stat.size, read_buf.len)]);

    // Write to destination
    const dest_file = try std.fs.cwd().createFile(dest_path[0..dest_len], .{});
    defer dest_file.close();
    try dest_file.writeAll(read_buf[0..bytes_read]);

    // Return filename
    const fn_len = @min(filename.len, name_out.len);
    @memcpy(name_out[0..fn_len], filename[0..fn_len]);
    return fn_len;
}

/// Build a full path for an icon: config_dir/icon_filename
pub fn iconFullPath(config_dir: []const u8, icon_name: []const u8, out: []u8) usize {
    if (icon_name.len == 0) return 0;

    // If already absolute, use as-is
    if (icon_name.len > 0 and icon_name[0] == '/') {
        const n = @min(icon_name.len, out.len);
        @memcpy(out[0..n], icon_name[0..n]);
        return n;
    }

    // Relative: config_dir/icon_name
    const total = config_dir.len + 1 + icon_name.len;
    if (total > out.len) return 0;
    @memcpy(out[0..config_dir.len], config_dir);
    out[config_dir.len] = '/';
    @memcpy(out[config_dir.len + 1 ..][0..icon_name.len], icon_name);
    return total;
}
