# DSHM DevEco Workspace

This bundle is a source-complete DSHM beta workspace prepared for DevEco Studio.

> **仅用于导出到另一台机器 / DevEco Studio GUI 环境。**
> 本机（鸿蒙 PC）没有 DevEco Studio GUI，开发、构建、安装全部走 `devecocli` 与 `tools/*.mjs`，
> 见 [`AGENT-HANDOFF.md`](AGENT-HANDOFF.md)。不要在本机照做本页的「First Run」。

## For AI Agents

Read `AGENTS.md` (rules and red lines) and then `AGENT-HANDOFF.md`
(toolchain commands, Beta/AGC build recipes, skills, default decisions, FAQ)
before doing anything. Do not ask the user how to build or install.

## First Run

1. Extract the archive to a short path without spaces or non-ASCII characters.
2. In the extracted directory, copy `build-profile.portable.json5` to `build-profile.json5`.
3. Open the directory, not a parent directory, in DevEco Studio.
4. Wait for project sync to finish. If dependencies are missing, run `ohpm install --all`.
5. Open `File > Project Structure > Signing Configs` and enable automatic signing for:
   - Product: `default`
   - Bundle name: `com.dshm.dshmbeta`
6. Select a connected HarmonyOS device (this project targets tablet / 2in1 / phone; no emulator workflow is used).
7. Build the `entry:default` HAP before changing application code.

## Included Build Inputs

- `entry/libs/arm64-v8a/`
- `entry/src/main/cpp/node-headers/`
- `entry/src/main/resources/resfile/`
- `third_party/`
- All current source, documents, tools, local tests, and Git metadata

## Intentionally Excluded

- `dist/`
- all `build/`, `.cxx/`, `.hvigor/`, `.idea/`, and `oh_modules/` directories
- `tmp-gp/`
- machine-bound `build-profile.json5` and `build-profile.local.json5`

The machine-bound profiles contain signing passwords and certificate paths. They
must never be copied to another machine. DevEco automatic signing creates a new
local profile for the new device.

## Safety

- Do not run `git clean`, `git reset --hard`, or delete `entry/libs`.
- Do not delete `entry/src/main/resources/resfile`; it contains required core,
  toolchain, and VM assets.
- Preserve the current worktree. The export includes uncommitted and untracked
  files.

See `docs/archive/211-迁移到DevEco-Studio与鸿蒙PC.md` for the full DevEco-Studio export checklist.
