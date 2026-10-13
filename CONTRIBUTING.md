# Contributing and Upstream Sync

This checkout is a personal fork of FlClash. Keep security work easy to review and straightforward to carry forward when the official repository changes. Read this guide before creating a change branch or syncing upstream.

The [Android security plan](docs/features/security/flclash_security_plan.md) is the entry point for iteration status and dependencies. The [security requirements](docs/features/security/security_requirements.md) define shared goals and decision criteria; preserve these requirements when syncing or resolving conflicts.

## Remote roles

- `origin`: the personal fork, `IdVincentYang/FlClash`.
- `upstream`: the canonical repository, `chen08209/FlClash`.
- Both remotes use the SSH host alias `github-vincent`, which resolves through the local SSH configuration.

The local remote URLs for this checkout are:

- `origin` → `git@github-vincent:IdVincentYang/FlClash.git`
- `upstream` → `git@github-vincent:chen08209/FlClash.git`

The README build commands continue to identify the canonical upstream source.

## Branch and change shape

1. Keep `main` aligned with `upstream/main`; advance it with fast-forward only.
2. Keep accepted Android work on the shared `security/android` integration branch. Merge official updates into that branch so earlier fixes remain present.
3. Start each security iteration on a short-lived branch from the current `security/android` branch, after reviewing the latest upstream changes. Integrate completed iterations back into `security/android`.
4. Keep commits narrow and organized by security finding or behavior. Avoid unrelated formatting, broad file replacement, and unnecessary generated-file changes.
5. If a fix must touch shared core code, a lockfile, or generated assets, record the upstream version it is based on, the reason for the local difference, and how to regenerate or verify it.
6. Keep one reviewable change set per iteration where practical, so upstream changes can be integrated without carrying unrelated security work together.

## Sync and conflict resolution

When the official repository advances:

1. Fetch the official remote, fast-forward local `main` from `upstream/main`, then merge `upstream/main` into the shared `security/android` branch.
2. Update iteration branches from `security/android`: rebase a private, unpublished branch; merge for a branch already shared with others instead of rewriting its history.
3. Resolve each conflict using the current upstream behavior and the security requirement together. Do not resolve by blindly choosing “ours” or “theirs”.
4. For a security-sensitive conflict, record the affected finding, the behavior retained, and the reasoning in that iteration's result or review notes.
5. Review the full branch diff against `upstream/main`; confirm that the sync did not remove a security behavior or introduce unrelated changes. Re-run focused checks for the affected paths and recheck dependency locks and data digests.
6. Do not force-push a shared branch. Preserve upstream history and keep fork-only changes as explicit commits that can be reviewed or ported.

This workflow keeps the security delta visible during every sync and gives reviewers a clear place to inspect conflict decisions.

## 中文说明：个人 fork 与官方同步

本仓库是 FlClash 的个人 fork。开始改动或同步官方更新前，请按本节操作；这样安全修复可以持续跟进官方新代码，也便于审查和解决冲突。[Android 安全总计划](docs/features/security/flclash_security_plan.md)管理阶段入口、状态与依赖，**[共同安全目标](docs/features/security/security_requirements.md)是同步和解决冲突时必须保留的需求依据**。

- `origin` 是个人仓库 `IdVincentYang/FlClash`；`upstream` 是官方仓库 `chen08209/FlClash`。
- 两个 remote 都使用本机 SSH 配置中的 `github-vincent` 别名；当前地址分别为 `git@github-vincent:IdVincentYang/FlClash.git` 和 `git@github-vincent:chen08209/FlClash.git`。
- `main` 只通过 fast-forward 跟进 `upstream/main`；`security/android` 是保留已完成 Android 改动的共享集成分支。每轮从当前集成分支建立短期分支，完成后合回集成分支。
- 按风险或行为拆分小提交；避免无关格式化、整文件替换和不必要的生成文件改动。必须改共享核心、锁文件或生成资产时，记录基于的官方版本、保留本地差异的原因及再生成/复核方法。
- 官方更新后先 fetch `upstream`，再 fast-forward 本地 `main`，将 `upstream/main` merge 到 `security/android`，保留已有安全修复。各整改分支再跟进集成分支：尚未发布且未共享的分支可以 rebase；已经共享的分支用 merge，避免改写他人历史。
- 冲突要结合当前官方行为和安全要求重新合并，不要直接选择 ours 或 theirs。安全相关冲突需在该轮结果或评审记录中写明涉及的风险编号、保留的行为和取舍原因。
- 同步后检查分支相对 `upstream/main` 的完整差异，确认安全行为没有丢失、没有带入无关改动；对受影响路径做定向验证，并重新核对依赖锁和数据摘要。不要强推共享分支。
