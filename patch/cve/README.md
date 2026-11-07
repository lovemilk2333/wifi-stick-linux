# CVE 本地提权修复补丁集

本目录收录了针对 Linux 5.15.0 基线内核、已合入 5.15.y 稳定分支的本地提权（LPE）CVE 修复补丁。

## 选取标准

- CVSS v3 攻击向量为 `AV:L`，权限要求为 `PR:L` 或 `PR:N`，且机密性/完整性影响为 `High`；
- 漏洞引入版本不晚于 5.15.0，且已有 5.15.y 稳定版本修复；
- 优先覆盖本内核配置实际启用、且普通用户可触达的子系统（netfilter、net/sched、io_uring、overlayfs、pipe、bpf、cgroup、fs 等）。

## 统计

- 5.15.y 中修复的 LPE CVE 候选：242 个；
- 核心/可触达候选：94 个；
- 本次合入：50 个（48 个稳定补丁直接应用，2 个因上下文差异手工应用）。

补丁来源：`https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git`（`linux-5.15.y`）。

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

> 说明：本仓库基于 5.15.0，仍有大量在 5.15.y 后续版本修复的 CVE 未覆盖。
> 完整覆盖建议升级到最新的 5.15.y 稳定版本，或继续按 `MANIFEST.tsv` 的方式分批回合。
