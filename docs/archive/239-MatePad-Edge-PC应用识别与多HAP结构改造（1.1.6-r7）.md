# 239 · MatePad Edge PC 应用识别与多 HAP 结构改造（1.1.6 r7）

> 日期：2026-10-24
>
> 依据：桌面上华为官方关于 MatePad Edge 不识别 PC 端 App 的回复
> `edge.txt`，以及 HarmonyOS 官方《module.json5配置文件》《HAP》《应用程序包概述》。
>
> 状态：结构改造已实施并生成 r7。应用版本保持 `1.1.6 / 1010006`。
>
> 结论：r6 的多 HAP 结构不满足 Edge PC 应用兼容要求；r7 已把
> PC、普通平板和 Edge 收敛为同一个 `tablet + 2in1` entry。

## 1. 官方要求

官方回复逐条要求：

1. 所有随应用交付的 Entry/Feature HAP 的 `deviceTypes` 必须包含目标设备类型；
2. MatePad Edge 的 PC 应用兼容需要同时声明 `tablet` 和 `2in1`；
3. AGC 分发必须同时勾选平板和 PC/2in1，并开启“兼容分发至 PC/2in1 的
   AppGallery”；
4. Edge 系统必须升级到 `6.1.0.135SP9 patch03` 或以上；
5. PC 系统能力、权限、API 与平板不一致，必须做运行时判断和降级。

这不是仅针对安装器的建议，而是应用包能否作为 PC 应用被 Edge 识别、分发和
运行的条件。

## 2. r6 为什么不满足

当前 r6：

| 模块 | 类型 | deviceTypes | 作用 |
|---|---|---|---|
| `entry` | entry | `2in1` | PC / 2in1 |
| `tablet` | entry | `tablet` | 平板 |
| `phone` | entry | `phone` | 手机 |
| `hostruntime` | shared | `phone/tablet/2in1` | 共享运行时 |

问题：

- `entry` 没有 `tablet`，不能作为 Edge 的 PC 兼容应用；
- `tablet` 没有 `2in1`，只能按普通平板应用安装；
- 应用内虽然识别 `QXS-* / MatePad Edge` 后强制 desktop UI，但它不会改变
  HAP 的安装身份；
- `tablet` HAP 也不包含 `CUSTOM_SANDBOX`、`ALLOW_EXTERNAL_NATIVE_CODE` 和两条
  2in1 kernel 能力，因此即使 Edge 上显示 desktop UI，原生终端/Codex 仍缺少
  PC HAP 的能力面。

## 3. 为什么不能只给 tablet 加 2in1

官方《HAP》文档明确：

> 多 HAP 场景下，App Pack 包中同一设备类型的所有 HAP 中最多只能包含一个
> Entry 类型的 HAP。

如果直接把当前 `tablet` 改为 `["tablet","2in1"]`：

- Edge 会同时命中 `entry(2in1)` 和 `tablet(tablet,2in1)`；
- 同一设备出现两个 entry HAP；
- 安装器返回 `9568287 install invalid number of entry hap`。

所以“`edge/` 目录是正式修复”的上一版判断不成立。它只能用于验证 tablet HAP
在当前设备上能否启动，不能用于 AGC PC 应用兼容。

## 4. r7 已实施结构

PC、普通平板和 MatePad Edge 已收敛为一个 desktop/tablet entry：

```text
entry                 deviceTypes = ["tablet", "2in1"]
phone entry           deviceTypes = ["phone"]
hostruntime shared    deviceTypes = ["phone", "tablet", "2in1"]
```

关键点：

1. 独立 `tablet` module 已从 `build-profile.json5` 移除，避免与双形态 entry 重叠；
2. PC 与 Edge 使用同一个 `entry-default.hap`，entry 内按 `DeviceFacts` 决定：
   - `QXS-* / MatePad Edge`：desktop UI、原生终端；
   - 普通平板：tablet 手持布局；
   - PC / 2in1：desktop UI；
3. `phone` 保持独立，避免手机被强制拉入 2in1 权限面；
4. shared HSP 三种设备类型齐全；
5. 特权权限的 2in1 限制仍需要内测组在普通平板验证安装，不能假设系统会
   自动忽略。

如果普通平板无法接受合并 HAP 的 2in1 权限，只能在以下产品决策中选一个：

- 不再用同一个 HAP 覆盖普通平板；
- 为 Edge/PC 与普通平板分开发布包；
- 经真机验证后去掉普通平板不需要的 2in1 权限。

不能靠增加第二个 tablet entry 绕开，因为那会重新违反“一设备类型一个 entry”。

## 5. AGC 与系统版本

代码改完后还必须同时满足：

- AGC 支持设备勾选平板和 PC/2in1；
- 勾选“兼容分发至 PC/2in1 的 AppGallery”并重新提交；
- Edge 系统 ≥ `6.1.0.135SP9 patch03`。

其中任一条件不满足，都可能表现为“PC 应用不识别”或安装入口不可用。

## 6. 安装与云调试

本地/云调试仍必须一次只装一个 entry HAP：

- 调整结构后，Edge 应使用新的双形态 entry HAP + shared HSP；
- 不能把包含 PC、平板、手机三个 entry 的 `all/` 或 `.app` 直接交给
  设备安装器；
- `9568287` 是本地安装层的多 entry 错误，与 AGC 的设备类型兼容是两个独立
  问题，但当前结构会同时触发两者。

## 7. 验收

结构改造后至少验证：

1. Edge 平板模式和 PC 模式下都由同一个 HAP 启动；
2. Edge 显示 desktop UI，原生终端、Codex、文件访问可用；
3. 普通平板仍使用 tablet 布局，安装不因 2in1 权限被拒；
4. PC/2in1 行为不回归；
5. 手机 HAP 不受影响；
6. AGC 包设备类型为 `phone / tablet / 2in1`，无重叠 entry；
7. 本地安装只传一个 entry HAP + shared HSP；
8. Edge 系统版本达到官方最低补丁。

## 8. r7 产物

| 项 | 值 |
|---|---|
| release APP | `dist/release-test/DSHM-1.1.6-multihap-3platforms-20261024-r7.app` |
| release size | `460,609,895 B` |
| release SHA-256 | `fe9b9828d20563d5d882744548782e8f4b6876dd60f3054f5c36246272c0567c` |
| debug APP | `dist/sideload/DSHM-1.1.6-multihap-3platforms-debug-20261024-r7.app` |
| debug size | `465,911,467 B` |
| debug SHA-256 | `4c55abc7fb9a120f6de51fc76e65f72ac0eb45d1fa1d023e2c514a4465a4652c` |
| Edge 两件包 | `dist/sideload/DSHM-1.1.6-MatePad-Edge-tablet-debug-r7.zip` |
| Edge ZIP SHA-256 | `2a4e91313899016ec9cc1fa1e6ce60d1479fedbc3ce8e69355789d0297583ba0` |
| core | `0.2.1-rc.2+dshm.90` |

APP 内仅有：

```text
entry-default.hap                  tablet,2in1
phone-default.hap                  phone
hostruntime-default.hsp            phone,tablet,2in1
```

三件均实现：

- `versionName=1.1.6`、`versionCode=1010006`；
- compatible API 23、target API 26；
- release 为 `buildMode=release / debug=false`；
- release/debug APP 均通过 `hap-sign-tool verify-app`。

## 9. 文档来源

- 桌面官方回复：`~/edge.txt`
- `module.json5`：
  <https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/module-configuration-file>
- HAP：
  <https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/hap-package>
- 应用程序包概述：
  <https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/application-package-overview>

当前 r7 已实施该结构改造；功能和设备兼容仍待内测组回归。

### Hokit 专用件

Hokit 若加载包含两个 entry 的 `.app`，可能只读取到 phone HAP 并提示
“该应用仅支持手机设备”。应直接加载：

```text
dist/sideload/DSHM-1.1.6-Edge-Hokit-r7/
  DSHM-1.1.6-Edge-tablet-2in1-debug.hap
  DSHM-1.1.6-Edge-hostruntime.hsp
```

该 HAP 内嵌 `module.json` 实读：

```json
"deviceTypes": ["tablet", "2in1"]
```

HAP SHA-256：
`12eae5b287d731099b3def76d4031e55d601d443dbf070f31a33dfe52f1899d1`。

### Pro MAX 对照

用户实测 MatePad Pro MAX 通过云调试使用同一双形态 entry 时可识别为 PC，
终端直接出现 `sh / zsh / bash` 且秒进。这说明：

- r7 的 PC entry、`DSHM_NATIVE_TERMINAL_ONLY=1` 和原生 PTY 链路本身正常；
- 问题发生在 Edge 的安装方式 / HAP 选择 / 系统 PC 兼容版本，而不是应用把
  Edge 错判成了 phone；
- Hokit 提示“仅支持手机设备”不能作为 HAP 清单结论，尤其不能拿多 entry
  `.app` 去判断。

Edge 复验应固定变量：使用上面文件名明确的 `tablet-2in1` HAP，通过
云调试或 `hdc install -r -p` 安装，并与 Pro MAX 使用同一 r7 包。

为了把“安装器预检”与“运行期设备识别”彻底分开，另生成了 PC-only `2in1`
诊断包：

```text
dist/sideload/DSHM-1.1.6-PC-only-2in1-r7/release/
  DSHM-1.1.6-PC-only-2in1-release.hap
  DSHM-1.1.6-PC-only-hostruntime-release.hsp
```

该 HAP 与 HSP 内部 `deviceTypes` 均为 `["2in1"]`，签名验证通过。构建后源码
已立即恢复为正式 r7 的 entry `["tablet","2in1"]` 与 HSP 三设备面；诊断口径
未留在正式工程。若这个包能安装，说明 Edge 已进入 PC 应用兼容模式；若 Hokit
仍报“仅支持手机”，即可确定是 Hokit 选中了别的包或预处理错误。
