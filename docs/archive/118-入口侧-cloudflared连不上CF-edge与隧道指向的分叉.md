# 118 入口侧施工单：cloudflared 连不上 CF edge（fake-ip/TUN 接管）与「控制台改了不生效」的分叉

> 配套：`docs/117-远程执行主机·飞牛NAS-Docker施工单.md`（主机侧）。
> 本篇只解决**入口侧**的一件事：**公网这条主机名没打到新的 `127.0.0.1:3111`**。

- 出具方：开发端（本仓维护者 / Codex）
- 施工方：飞牛 NAS 侧 Agent（Hermes）
- 日期：2026-10-08
- 现状一句话：**`docs/117` 的容器已就绪（自验收 10/10）**，但公网这条主机名仍落在**旧服务**上；
  且 NAS 上的 `cloudflared` 自 **2026-10-08T07:50:52Z** 起持续 `TLS handshake with edge error: EOF`，
  最后一次 `Updated to new configuration` 停在 **2026-09-25T04:20:25Z`。

---

## 0. 交付边界

**Hermes 负责**：判定这条 tunnel 的**管理形态** → 按对应分叉把 `127.0.0.1:3111` 真正接上 → 贴回读数。
**Hermes 不负责**：不动 dsh 侧（容器 / `--trusted-host` / token）；不动 3080 上原有的 `dsh-web.service`；
不碰手机；不改写任何 HTTP 头（§117 §3.6.3 明令）。

**红线**：

1. 改 mihomo/Fluxor 配置**只增不删**，改前先备份，`reload` 前必须先做配置校验；
2. **不要**为了"绕开"而删/改 `Host` 头，也**不要**把 dsh 绑到 `0.0.0.0`；
3. 不删任何数据、不卸载、不动签名物料；
4. 3080 那个服务如果还要对外，**给它另起一个子域名**，别与这条抢名字。

---

## 1. 现象与证据（都已在 `docs/117` §14 登记，这里只列判据）

| # | 观测 | 读数 | 含义 |
|---|---|---|---|
| 1 | 公网 `GET https://<INGRESS_HOST>/?token=<3111 的 token>` | **401，无 `Set-Cookie`** | `/` 不受栅栏保护、只比 token ⇒ **没打到 3111** |
| 2 | 公网 `GET https://<INGRESS_HOST>/?token=<3080 的 token>` | **303 + `Set-Cookie`** | 公网这条主机名**落在 3080 的旧进程**上 |
| 3 | 公网 WS 升级 `GET /api/remote.mux`（`Host`/`Origin` = 入口名，不带 cookie） | **403 `text/plain`** | 收到请求的进程**不信任**这个 authority（3080 没配 `--trusted-host`） |
| 4 | NAS：cloudflared 日志 | `TLS handshake with edge error: EOF` + `Retrying connection in up to 1m4s` | 到 CF edge 的连接不稳 |
| 5 | NAS：`getent hosts argotunnel.com` → `198.18.0.165`；`ip route get 198.18.0.165` → `… dev Meta table 2022` | fake-ip 段（`198.18.0.0/15`）+ TUN 接管 | 解析被 mihomo 接管（**机制待定论**） |

> 注意 #1/#2 与"隧道到底连没连上"**不矛盾**：容器里的 dsh 一直在服务，说明**至少有一条连接是活的**
> （CF 会给同一条 tunnel 建多条 edge 连接）。所以**不能**用"日志在报错"推断"完全没通"。

---

## 2. 【先做这一步】判定管理形态 —— 决定后面完全不同的两条路

CF Tunnel 的 ingress 有两种来源，**行为完全不同**：

| 形态 | 识别 | ingress 在哪 | "控制台改了不生效"的原因 |
|---|---|---|---|
| **A 本地管理** | systemd/命令行里**没有** `--token`；存在 `config.yml` | NAS 上的 `config.yml` 的 `ingress:` | 控制台的编辑**根本不参与**（控制台只对远端管理的 tunnel 生效）⇒ 必须**改文件** |
| **B 远端管理** | 命令行/unit 里有 `--token <…>`（或 `tunnel run --token`） | CF 控制台 | 连接器**连上 edge 时**才会拉配置 ⇒ 连不上就永远用旧配置 |

**判定命令**（三选一，贴回输出）：

```bash
systemctl cat cloudflared 2>/dev/null | grep -E 'ExecStart|token'
ps -o pid,args= -C cloudflared | head -5
ls -l /etc/cloudflared/ /root/.cloudflared/ 2>/dev/null
```

再看它**现在到底在按什么配置跑**：

```bash
# 指标端口（回执里是 19991；不是这个就按实际）
curl -s http://127.0.0.1:19991/metrics | grep -E 'cloudflared_tunnel_ha_connections|cloudflared_tunnel_total_requests' | head
# 形态 A 才有的文件；形态 B 通常没有 ingress（或只有占位）
sudo grep -n -A20 '^ingress:' /etc/cloudflared/config.yml 2>/dev/null
```

**判读**：

- `ha_connections >= 1` ⇒ **连接器是连着的** ⇒ 它按**当前生效的配置**提供服务；
  此时"公网还打到 3080"就说明**它手上的配置写的就是 3080** ⇒ 大概率是**形态 A**，或形态 B 但拉到的还是旧配置。
- `ha_connections = 0` ⇒ 真断了（那就不该有人应答；若仍有人应答，说明**还有第二个连接器**，先查清楚再动手）。

---

## 3. 施工：按形态分叉

### 3.1 形态 A（本地 `config.yml` 管理）——**首选**，与 DNS/代理无关

```bash
CFG=/etc/cloudflared/config.yml          # 按实际路径改
sudo cp -a "$CFG" "$CFG.bak.$(date +%F-%H%M)"
sudo sed -i 's#^\( *\)- service: *http://192\.168\.2\.88:3080#\1- service: http://127.0.0.1:3111#' "$CFG"
sudo grep -n -B2 -A2 'service:' "$CFG"          # 复核：这条主机名的 service 已是 http://127.0.0.1:3111

cloudflared tunnel ingress validate             # 期望 configuration file is valid
cloudflared tunnel ingress rule https://<INGRESS_HOST>/   # 期望命中 → http://127.0.0.1:3111
sudo systemctl restart cloudflared              # 形态 A 改了文件必须重启（不是 reload）
sleep 5; journalctl -u cloudflared -n 30 --no-pager | grep -E 'Updated to new configuration|Registered tunnel connection'
```

> ⚠️ `ingress rule` 的匹配是**自上而下取第一条**：确认没有更靠前的 `- hostname:` 把这条主机名抢走
> （同一条 tunnel 里两个 hostname 指向不同回源时，CF 只认**先匹配**的那条 —— 这也是"抢名字"的隐患）。

**做完直接跳到 §5 验证。**

### 3.2 形态 B（控制台/`--token` 管理）—— 必须让连接器能连上 edge

只有在**形态 B** 且日志持续 `TLS handshake with edge error: EOF` 时才动 mihomo。顺序：

1. 先在**控制台**确认这条 hostname 的 origin 是 `http://127.0.0.1:3111`
   （Zero Trust → Networks → Tunnels → 选中该 tunnel → Public Hostnames）；
2. 按 §4 修 mihomo，让 `cloudflared → CF edge` 这一跳通；
3. 修完**优先等它自己重连**（它本来就在退避重试）；10 分钟内没动静再 `sudo systemctl restart cloudflared`。

---

## 4. mihomo / Fluxor 侧修法（**只增不删**；先证伪再改）

### 4.1 先证明"是 fake-ip 在捣鬼"（一条命令对照）

```bash
getent hosts argotunnel.com                    # 走系统解析（= mihomo 的 DNS）→ 现在回 198.18.0.165（fake-ip）
dig @1.1.1.1 argotunnel.com +short 2>/dev/null || nslookup argotunnel.com 1.1.1.1
                                               # 直查外部 DNS → 应回**真实** CF 地址（104.x / 172.6x 等）
```

> **判据**：前者是 `198.18.x.x` 而后者是真实地址 ⇒ **解析被 fake-ip 接管**（这是必要条件，不是充分条件）。
> 若两者都回真实地址，说明 DNS 这条没被接管 —— 那就**不要**改 fake-ip-filter，去查 §4.4。

### 4.2 改两处（**两条一起做，缺一条可能仍不通**）

```yaml
# ① DNS：不要让这些域名拿 fake-ip（按你的版本支持的写法，两种写法都写上，校验报错就删掉不支持的那条）
dns:
  fake-ip-filter:
    - "+.argotunnel.com"
    - "*.argotunnel.com"

# ② 策略：让它**不走代理**（fake-ip 只管"给什么 IP"，走不走代理由 rules 决定）
rules:
  - DOMAIN-SUFFIX,argotunnel.com,DIRECT     # ← 放在你现有规则**之前**（mihomo 自上而下取第一条）
  # …以下保留你原有规则，一行都不要删…
```

> ⚠️ **只加 `argotunnel.com`**：`cloudflared` 连的就是 `*.argotunnel.com`。
> **不要**顺手把 `cloudflare.com` 整域改成 DIRECT —— 那会改变你其它流量的走向（本次不需要）。

### 4.3 校验与生效

```bash
mihomo -t -f /etc/mihomo/config.yaml      # 或你发行版的等价命令（Fluxor 自带的"配置检查"）——必须先绿
# 生效：用 Fluxor 自带的重载入口（面板/API 的「重载配置」）最稳；没有就 systemctl restart <mihomo 服务>
#   ⚠️ restart 会短暂断网；家里还有别人在用就挑时间
```

重载后**立刻复跑 §4.1 的两条命令**：`getent hosts argotunnel.com` 应变成真实地址，
且 `ip route get <该真实地址>` 不再出现 `dev Meta`。

### 4.4 若 §4.1 已经是真实地址、但握手仍 EOF（备选修法）

说明"DNS 没被接管，但连接仍被送进了代理/被中途干预"。此时**不要**再改 DNS，改**按进程放行**：

```yaml
rules:
  - PROCESS-NAME,cloudflared,DIRECT          # 需要 mihomo 的进程匹配开启（find-process-mode: strict）且有权限
```

同理只增这一条、放在最前、校验后重载。若你的 mihomo 版本不支持进程规则，就在**防火墙/路由**层
给 cloudflared 的出口放行（这属于你的网络栈，按现场条件处理），**并把改动原文贴回**。

---

## 5. 验证清单（改完立刻跑；每行都要贴回读数）

**先记基线**（改动前的现值）：公网 `/` = `401`；公网 WS 升级 = `403`。

```bash
NAME='<INGRESS_HOST>'
BASE='http://127.0.0.1:3111'
TOKEN='<3111 容器的当前 token（取法见 docs/117 §6.6）>'

# V118-1 解析已回到真实地址（形态 B 才需要）
getent hosts argotunnel.com

# V118-2 连接器活着且已拉到新配置（形态 B 才需要）
journalctl -u cloudflared -n 50 --no-pager | grep -E 'Updated to new configuration|Registered tunnel connection|TLS handshake'
curl -s http://127.0.0.1:19991/metrics | grep cloudflared_tunnel_ha_connections

# V118-3 回源已指向 3111（形态 A 用文件、形态 B 用控制台核对）
cloudflared tunnel ingress rule "https://$NAME/"       # 形态 A 期望命中 → http://127.0.0.1:3111

# V118-4 loopback 侧不回归（这两条应与 docs/117 §14.1 一致）
curl -s -o /dev/null -w 'root=%{http_code}\n' "$BASE/?token=$TOKEN"                       # 期望 303
COOKIE_N=$(curl -s -D - -o /dev/null -H "Host: $NAME" "$BASE/?token=$TOKEN" | tr -d '\r' | awk '/^set-cookie:/I {print $2; exit}')
node /srv/dsh/config/verify-ws.mjs "$COOKIE_N" "$NAME" "https://$NAME"                   # 期望 101
```

**外部侧**（从手机流量或另一台机器跑，别在 NAS 上自连自）：

```bash
curl -s -o /dev/null -w 'public_root=%{http_code}\n' "https://$NAME/"                    # 期望 401（dsh 的认证提示）
curl -sD - -o /dev/null "https://$NAME/?token=$TOKEN" | head -5                          # 期望 303 + Set-Cookie
# 下面这条的 cookie 在 NAS 上换好（V118-4 那份），再把脚本与 cookie 拷到这台外部机器 —— cookie 绑的是
# 「入口名」这个 authority，与客户端 IP 无关；verify-ws.mjs 只用 Node 内置模块
node verify-ws.mjs "$COOKIE_N" "$NAME" "https://$NAME"                    # 期望 101（单值同源）
node verify-ws.mjs "$COOKIE_N" "$NAME" "https://$NAME, wss://$NAME"       # 期望 101（鸿蒙多值形态）
```

**V118-5（决定性）**：外部侧 `?token=` 从 **401 → 303** 的那一刻，说明**隧道真的打到 3111 了**。
之后手机端到端（ConnectPane 粘 URL → 起会话 → 跑一条 `bash`）由**开发端**做。

**若外部侧 WS 是 `403` 而 loopback 的 V118-4 是 `101`**：那是"到达 dsh 的 `Host` ≠ 声明的入口名"
（cloudflared 侧改写了 Host）⇒ 处置见 `docs/117` §4 末尾第 5 条（把 `originRequest.httpHostHeader`
设为入口名；或把实际到达的 authority 也加进 `--trusted-host`）。**仍然不要改 Host 头去绕。**

---

## 6. 必须贴回开发端的东西

1. §2 的形态判定输出（`systemctl cat` / `ps -o args=` 的**关键行**，token 打码）；
2. `ha_connections` 的读数与 cloudflared 日志里那三类的**时间戳**；
3. 形态 A：`ingress rule` 命中结果；形态 B：mihomo 改动的**原文前后**（含备份路径）；
4. §5 的**全部读数**（含基线对照）；
5. 若走了 §4.4，附上替代修法的原文与结果。

**边界**：手机端到端由开发端做；NAS 侧不用动手机，也不用动 dsh 容器。
