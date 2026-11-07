# CVE 本地提权修复补丁集

本目录收录了针对 Linux 5.15.0 基线内核、已合入 5.15.y 稳定分支的本地提权（LPE）CVE 修复补丁。

## 选取标准

- CVSS v3 攻击向量为 `AV:L`，权限要求为 `PR:L` 或 `PR:N`，且机密性/完整性影响为 `High`；
- 漏洞引入版本不晚于 5.15.0，且已有 5.15.y 稳定版本修复；
- 优先覆盖本内核配置实际启用、且普通用户可触达的子系统（netfilter、net/sched、io_uring、overlayfs、pipe、bpf、cgroup、fs 等）。

## 统计

- 5.15.y 中修复的 LPE CVE 候选：1845 个（含非核心子系统）；
- 核心/可触达候选：第一批 94 个，第二批 452 个；
- 已合入：443 个
  - 第一批 50 个（48 个稳定补丁直接应用，2 个手工应用）；
  - 第二批 338 个（316 个直接应用，8 个适配 5.15.0 API，14 个手工移植）；
  - 第三批 29 个（25 个借助上下文模糊匹配应用，3 个适配 5.15.0 API，1 个手工移植）；另有 1 个确认 5.15.0 本已修复。
  - 第四批 26 个（17 个手工移植，9 个借助上下文模糊匹配应用）；另有 1 个确认 5.15.0 本已修复。
- 尚未合入：57 个（见 `CONFLICTS.tsv`，多为依赖前置重构或目标功能在本内核配置中未启用）。

补丁来源：`https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git`（`linux-5.15.y`）。

## 批次说明

### 第一批（50 个）

覆盖 5.15.0 → 5.15.149 之间修复、且属于核心可触达子系统的 LPE。

### 第二批（338 个）

覆盖 5.15.150 → 5.15.224 以及第一批遗漏的早期核心 CVE，按修复版本升序多轮应用。
其中 8 个补丁使用了 5.15.0 中不存在的 API，已在本地适配：

| CVE | 适配内容 |
| --- | --- |
| CVE-2026-64015 | `guard(rcu)()` → 显式 `rcu_read_lock()/rcu_read_unlock()` |
| CVE-2026-64560 | 同上 |
| CVE-2026-72389 | `timer_shutdown_sync()` → `del_timer_sync()` |
| CVE-2026-74594 | 同上 |
| CVE-2024-26601 | `ext4_mb_generate_buddy()` 适配 4 参数签名 |
| CVE-2026-63828 | 新增 `sk_is_inet()` 辅助函数 |
| CVE-2026-52988 | 新增 `__list_splice_rcu()` / `list_splice_rcu()` |
| CVE-2025-21759 | 新增 `read_pnet_rcu()` / `dev_net_rcu()` |

14 个手工移植的 CVE 见 `MANIFEST.tsv` 中 `status=MANUAL` 的行。

### 第三批（29 个）

在第二批基础上，对剩余冲突项使用上下文模糊匹配（`patch --fuzz`）重新尝试，并对少量 API 差异做适配：

| CVE | 适配内容 |
| --- | --- |
| CVE-2023-52707 | 新增 `wake_up_pollfree()` / `__wake_up_pollfree()`（`POLLFREE` 支持） |
| CVE-2024-57996 | `sfq_change()` 增加 `extack` 参数 |
| CVE-2026-31407 | 回移 `NLA_BE16` / `NLA_BE32` 属性类型及范围校验 |
| CVE-2025-21758 | 手工移植到 `mld_newpack()`，并新增 `dst_dev_rcu()` 供 `nf_queue` 使用 |
| CVE-2024-38612 | 确认 5.15.0 已无条件调用 `genl_unregister_family()`，不受影响 |

### 第四批（26 个）

在第三批基础上继续移植剩余可安全落地的冲突项，重点覆盖 ext4/f2fs、mm（swap/khugepaged/hugetlb）、BPF、netfilter、packet socket 与 procfs。详见 `MANIFEST.tsv` 中 `status=MANUAL` / `APPLIED_FUZZ` 的第四批记录。

`MANIFEST.tsv` 为完整清单，`status` 取值：

- `APPLIED`：稳定分支补丁直接应用；
- `APPLIED_FUZZ`：借助上下文模糊匹配应用，已逐条人工核对落点；
- `ADAPTED`：直接应用但需适配 5.15.0 API 或补充辅助函数；
- `MANUAL`：因上下文差异手工移植；
- `CONFLICT`：未合入（仅记录于 `CONFLICTS.tsv`）；
- `NOT_AFFECTED`：经核对该 CVE 在 5.15.0 中不存在。

## 补丁清单

| 修复版本 | CVE | 稳定分支提交 | 说明 |
| --- | --- | --- | --- |
| 5.15.12 | CVE-2022-4744 | `3cb5ae77799e` | tun: avoid double free in tun_free_netdev |
| 5.15.14 | CVE-2021-4197 | `c6ebc3529884` | cgroup: Use open-time credentials for process migraton perm checks |
| 5.15.16 | CVE-2022-0185 | `e192ccc17ecf` | vfs: fs_context: fix up param length parsing in legacy_parse_param |
| 5.15.19 | CVE-2022-24122 | `348a8501e602` | ucount:  Make get_ucount a safe get_user replacement |
| 5.15.20 | CVE-2022-0492 | `4b1c32bfaa02` | cgroup-v1: Require capabilities to set release_agent |
| 5.15.20 | CVE-2022-1055 | `f36cacd6c933` | net: sched: fix use-after-free in tc_new_tfilter() |
| 5.15.25 | CVE-2022-0847 | `114e9f141822` | lib/iov_iter: initialize "flags" in new pipe_buffer |
| 5.15.26 | CVE-2022-25636 | `6c5d780469d6` | netfilter: nf_tables_offload: incorrect flow offload action array size |
| 5.15.29 | CVE-2022-0995 | `1b09f28f70a5` | watch_queue: Fix filter limit check |
| 5.15.29 | CVE-2022-1011 | `ca62747b38f5` | fuse: fix pipe buffer lifetime for direct_io |
| 5.15.31 | CVE-2022-20368 | `a055f5f2841f` | net/packet: fix slab-out-of-bounds access in packet_recvmsg() |
| 5.15.32 | CVE-2022-1016 | `fafb904156fb` | netfilter: nf_tables: initialize registers in nft_do_chain() |
| 5.15.33 | CVE-2022-30594 | `b6d75218ff65` | ptrace: Check PTRACE_O_SUSPEND_SECCOMP permission on PTRACE_SEIZE |
| 5.15.34 | CVE-2022-29582 | `ba7261af2b03` | io_uring: fix race between timeout flush and removal |
| 5.15.36 | CVE-2022-29581 | `ba9e9a794fd1` | net/sched: cls_u32: fix netns refcount changes in u32_change() |
| 5.15.45 | CVE-2022-1966 | `f692bcffd1f2` | netfilter: nf_tables: disallow non-stateful expression in sets earlier |
| 5.15.45 | CVE-2022-2959 | `cf2fbc56c478` | pipe: Fix missing lock in pipe_resize_ring() |
| 5.15.51 | CVE-2023-2008 | `5b45535865d6` | udmabuf: add back sanity check |
| 5.15.54 | CVE-2022-34918 | `c1784d207513` | netfilter: nf_tables: stricter validation of element data |
| 5.15.61 | CVE-2022-2586 | `faafd9286f13` | netfilter: nf_tables: do not allow SET_ID to refer to another table |
| 5.15.61 | CVE-2022-2588 | `57bbb691a93b` | net_sched: cls_route: remove from list when handle is 0 |
| 5.15.66 | CVE-2022-20421 | `c2a4b5dc8fa7` | binder: fix UAF of ref->proc caused by race condition |
| 5.15.78 | CVE-2023-3812 | `dcc79cf735b8` | net: tun: fix bugs for oversize packet when napi frags enabled |
| 5.15.82 | CVE-2022-4378 | `48642f94311b` | proc: proc_skip_spaces() shouldn't think it is working on C strings |
| 5.15.89 | CVE-2023-0179 | `a8acfe2c6fb9` | netfilter: nft_payload: incorrect arithmetics when fetching VLAN header bits |
| 5.15.91 | CVE-2023-0386 | `e91308e63710` | ovl: fail on invalid uid/gid mapping at copy up |
| 5.15.95 | CVE-2023-1281 | `becf55394f6a` | net/sched: tcindex: update imperfect hash filters respecting rcu |
| 5.15.109 | CVE-2023-2163 | `e722ea6dae2c` | bpf: Fix incorrect verifier pruning due to missing register precision taints |
| 5.15.109 | CVE-2023-31436 | `1ffc0e810551` | net: sched: sch_qfq: prevent slab-out-of-bounds in qfq_activate_agg |
| 5.15.111 | CVE-2023-32233 | `21c2a454486d` | netfilter: nf_tables: deactivate anonymous set from preparation phase |
| 5.15.116 | CVE-2023-35788 | `45f47d2cf114` | net/sched: flower: fix possible OOB write in fl_set_geneve_opt() |
| 5.15.118 | CVE-2023-3117 | `44ebe988cb38` | netfilter: nf_tables: incorrect error path handling with NFT_MSG_NEWRULE |
| 5.15.118 | CVE-2023-3609 | `0e1098d72fa4` | net/sched: cls_u32: Fix reference counter leak leading to overflow |
| 5.15.121 | CVE-2023-35001 | `870dcc31c0cf` | netfilter: nf_tables: prevent OOB access in nft_byteorder_eval |
| 5.15.121 | CVE-2023-3611 | `91d3554ab1fc` | net/sched: sch_qfq: account for stab overhead in qfq_enqueue |
| 5.15.121 | CVE-2023-3776 | `5b55f2d6ef40` | net/sched: cls_fw: Fix improper refcount update leads to use-after-free |
| 5.15.123 | CVE-2023-3777 | `10013f764ad2` | netfilter: nf_tables: skip bound chain on rule flush |
| 5.15.123 | CVE-2023-4004 | `706ce3c81b5c` | netfilter: nft_set_pipapo: fix improper element removal |
| 5.15.126 | CVE-2023-4128 | `262430dfc618` | net/sched: cls_u32: No longer copy tcf_result on update to avoid use-after-free |
| 5.15.126 | CVE-2023-4206 | `79c3d81c9ad1` | net/sched: cls_route: No longer copy tcf_result on update to avoid use-after-free |
| 5.15.126 | CVE-2023-4207 | `9edf7955025a` | net/sched: cls_fw: No longer copy tcf_result on update to avoid use-after-free |
| 5.15.132 | CVE-2023-42753 | `a9e6142e5f8f` | netfilter: ipset: add the missing IP_SET_HASH_WITH_NET0 macro for ip_set_hash_netportnet.c |
| 5.15.132 | CVE-2023-4623 | `4cf994d3f4ff` | net/sched: sch_hfsc: Ensure inner classes have fsc curve |
| 5.15.132 | CVE-2023-4881 | `1ad7b189cc14` | netfilter: nftables: exthdr: fix 4-byte stack OOB write |
| 5.15.132 | CVE-2023-4921 | `6ea277b2c626` | net: sched: sch_qfq: Fix UAF in qfq_dequeue() |
| 5.15.142 | CVE-2023-6932 | `c4a00c47a140` | ipv4: igmp: fix refcnt uaf issue when receiving igmp query packet |
| 5.15.147 | CVE-2023-6040 | `ab3a3aadb373` | netfilter: nf_tables: Reject tables of unsupported family |
| 5.15.148 | CVE-2023-52438 | `8ad4d580e8af` | binder: fix use-after-free in shinker's callback |
| 5.15.148 | CVE-2024-1085 | `c9ed30eea4f7` | netfilter: nf_tables: check if catch-all set element is active in next generation |
| 5.15.149 | CVE-2024-1086 | `960cf4f81253` | netfilter: nf_tables: reject QUEUE/DROP verdict parameters |

> 说明：本仓库基于 5.15.0，仍有 57 个已确认的 LPE CVE 未覆盖（见 `CONFLICTS.tsv`），
> 这些补丁大多依赖 5.15.y 后续版本中的前置重构，或目标功能在本内核配置中未启用。
> 完整覆盖建议升级到最新的 5.15.y 稳定版本，或按 `MANIFEST.tsv` 的方式继续分批回合。
