# Xcode workflow for ShellCraft

Use stable Xcode at `/Applications/Xcode.app/Contents/Developer`. XcodeBuildMCP is pinned to 2.7.0; upgrade it deliberately, separately from a release.

After changing MCP configuration, restart the agent/client so its tool catalog refreshes. From the active managed worktree, run `setup-xcode-mcp --check` before Apple-platform work. Use `setup-xcode-mcp --open "./ShellCraft.xcodeproj"` to open that project through the supported native Xcode MCP command when the native server needs a workspace. Do not use a GUI for build or release operations.

The default project is `ShellCraft.xcodeproj`, scheme `ShellCraft`, configuration Debug. Use the macOS destination. Select devices by their current names; never persist simulator UDIDs.

Use native Xcode MCP for supported project, build, test, preview, and runtime operations. Use XcodeBuildMCP for capabilities the native server does not expose. At the first XcodeBuildMCP action, call `session_show_defaults`. If the project, scheme or destination is missing or stale, call `session_set_defaults` with the active worktree’s resolved physical project path, scheme and destination, and `persist: false`, before invoking an action. Do not reuse another checkout’s paths or settings. For a run, use the combined build-and-run operation.

Use Codex native controls for app and simulator UI interaction. The project configuration does not add the `ui-automation` or `xcode-ide` proxy workflow. Do not start a second native bridge or Device Hub instance.

If native MCP access is unavailable, report its exact readiness or capability failure. Use the pinned XcodeBuildMCP CLI only as the documented CLI fallback for a necessary development operation, with the same `DEVELOPER_DIR`, worktree, scheme, and destination. Do not silently alternate between tools or switch to beta Xcode. Full app builds are not required to validate configuration-only changes.

Production release routing is described below. Development configuration changes do not authorize an upload or submission. Preserve the repo’s clean-source, signed-artifact, tag, review, entitlement, and beta-toolchain guards. Never use a GUI for build or release operations.

This macOS app currently uses root `release.sh` for its documented distribution path. Verify its actual supported route before any release; do not replace notarization or other existing distribution features with an assumed App Store submission.
