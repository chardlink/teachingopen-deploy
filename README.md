# TeachingOpen 2.8 Ubuntu / 群晖 本地部署说明

这个目录是一套独立的 `TeachingOpen 2.8` 自部署包，目标是：

- 不依赖宝塔
- 支持 Ubuntu 本地一键部署
- 支持群晖 `Container Manager` 项目式部署
- 数据全部保存在你自己的机器上
- 前端、后端、数据库、Redis 都本地化运行

## 适用范围

当前这套部署包适用于：

- Ubuntu 服务器
- 本地局域网环境
- 动态公网 IP + 路由器端口映射
- 群晖 NAS 容器部署

## 这套部署包做了什么

- 使用 Docker Compose 部署 `MySQL + Redis + Java + Nginx + kkFileView`
- 文件上传改为本地存储，不依赖七牛云
- 前端自动解压并修补
- 去掉默认外部 `errlog.js`
- 文件预览改为本地容器代理
- 首次启动时自动导入并清洗官方 SQL
- 兼容 Linux 表名大小写问题

## 不能改成什么

当前 `TeachingOpen 2.8` 是已经编译好的 Java 程序，后端本身硬依赖：

- MySQL
- Redis

所以它不能直接切换成纯 YAML / 纯 JSON 持久化，除非重写后端。

## 目录结构

- `assets/`
  - 原始 `jar`、前端 `zip`、数据库 `sql`
- `config/`
  - 后端挂载配置
- `docker/`
  - Nginx / MySQL 配置
- `scripts/`
  - 辅助脚本
- `data/`
  - 持久化数据目录
- `runtime/web-root/`
  - 自动解压后的前端静态文件

## Ubuntu 一键部署

1. 把整个目录复制到 Ubuntu。
2. 进入该目录。
3. 执行：

```bash
chmod +x install.sh start.sh stop.sh logs.sh status.sh backup.sh reconfigure.sh bootstrap-from-github.sh scripts/*.sh
sudo ./install.sh
```

安装脚本会自动：

- 安装 Docker（如果未安装）
- 生成 `.env`（如果不存在）
- 显示默认端口和访问地址
- 询问你是否使用默认值或改成自定义值
- 询问你是否要手动打开 `.env` 再修改一次
- 自动解压并修补前端静态包
- 启动全部容器

## 部署时会提示你填写什么

首次部署时，脚本会先显示默认值：

- `WEB_PORT=8080`
- `APP_DEBUG_PORT=18080`
- `PUBLIC_BASE_URL=http://服务器IP:8080`

然后你可以选择：

- 直接使用默认值
- 逐项输入新的端口和地址
- 先生成 `.env`，再手动打开 `.env` 修改后继续部署

如果目录里已经存在 `.env`，脚本会先显示当前配置，并询问你是否先手动修改。

## 默认访问方式

- 前端入口：`http://服务器IP:WEB_PORT`
- 后端本机调试入口：`http://127.0.0.1:APP_DEBUG_PORT/api/`

默认测试账号：

- `admin`
- `teacher`
- `student`

默认密码：

- `123456`

## 常用命令

启动：

```bash
./start.sh
```

停止：

```bash
./stop.sh
```

查看日志：

```bash
./logs.sh
./logs.sh app
```

查看状态：

```bash
./status.sh
```

备份：

```bash
./backup.sh
```

## 后续修改端口和外网入口

不需要重新安装。

后续如果你想改：

- 本机服务端口 `WEB_PORT`
- 本机调试端口 `APP_DEBUG_PORT`
- 外网入口 `PUBLIC_BASE_URL`

直接执行：

```bash
./reconfigure.sh
```

这个脚本会自动：

- 显示当前 `WEB_PORT`
- 显示当前 `APP_DEBUG_PORT`
- 显示当前 `PUBLIC_BASE_URL`
- 提示你输入新的本机端口
- 提示你输入新的外网入口协议、主机和端口
- 自动写回 `.env`
- 自动执行一次 `stop` 再 `start`

## PUBLIC_BASE_URL 是做什么的

`PUBLIC_BASE_URL` 不是监听地址，而是系统“默认对外使用的地址”。

它主要影响：

- 后端默认站点地址
- 文件预览服务地址
- 少数绝对链接、分享链接、跳转地址

它不是必须和实际监听端口完全相同，但它最好代表你希望系统默认对外暴露的入口。

### 推荐理解方式

- `WEB_PORT`
  - 服务器本机真正监听的端口
- `PUBLIC_BASE_URL`
  - 浏览器和系统默认认为的对外访问入口

## 内网访问和外网访问能否同时存在

可以。

例如：

- 服务器内网 IP：`192.168.1.50`
- 本机监听端口：`8080`
- 路由器外网映射端口：`28080`

那么：

- 内网访问：`http://192.168.1.50:8080`
- 外网访问：`http://公网IP:28080`

两者可以同时存在。

## 内外网端口不一致是否可行

完全可行。

例如：

- 本机：`8080`
- 外网映射：`28080 -> 8080`

这是标准做法。

你不必使用 `80` 端口。

## 动态公网 IP 是否必须固定

不需要固定公网 IP。

如果你的公网 IP 经常变化，推荐优先使用：

- DDNS 动态域名

例如：

```env
PUBLIC_BASE_URL=http://你的DDNS域名:28080
```

然后路由器做：

- 外网 `28080` -> 内网 `8080`

这样即使公网 IP 变化，外部访问地址也不用反复改。

## 如果我不想频繁改 PUBLIC_BASE_URL 怎么办

可以把它固定成某个“主入口”：

### 情况 1：主要内网使用，偶尔外网访问

可以写成内网地址：

```env
PUBLIC_BASE_URL=http://192.168.1.50:8080
```

这样：

- 内网访问最稳
- 外网用户仍然可以手动用公网入口打开页面

但要注意：

- 少数绝对链接、预览、跳转可能仍然指向内网地址

### 情况 2：希望外网功能更稳

更推荐写成：

- DDNS 域名
- 公网 IP + 外网映射端口

例如：

```env
PUBLIC_BASE_URL=http://你的DDNS域名:28080
```

## 只要不是 localhost，内网地址也能给公网用户用吗

不能这样理解。

要区分：

- `localhost` / `127.0.0.1` / `127.0.1.1`
  - 只有服务器自己能访问
- `192.168.x.x` / `10.x.x.x`
  - 只有内网能访问
- 公网 IP / DDNS 域名
  - 外网用户才能访问

如果你把 `PUBLIC_BASE_URL` 写成内网地址：

```text
http://192.168.1.50:8080
```

那么公网浏览器拿到这个地址后，不会“自动绕回公网”，而是会直接去访问私网地址，结果通常失败。

所以：

- 不是“只要不是 localhost 就可以”
- 私网地址也不适合直接作为公网用户的默认入口

## 推送到 GitHub 后的一键下载部署

可以实现。

推荐做法是：把当前整个 `TeachingOpen2.8-ubuntu-local-deploy` 目录单独作为一个 GitHub 仓库根目录。

这样后续在 Ubuntu 上只要一条命令就能：

- 下载仓库
- 或更新仓库
- 然后继续执行部署

注意：当前仓库里的大文件资源使用了 `Git LFS`，因为官方 `jar` 和前端 `zip` 都超过普通 GitHub 单文件限制。

脚本文件是：

```bash
./bootstrap-from-github.sh
```

### 方式 1：公开仓库，直接做成 HUSTOJ 风格一键命令

如果你的仓库是公开的，那么可以直接像 `HUSTOJ` 那样执行远程脚本。

先下载再执行：

```bash
wget -O teachingopen-bootstrap.sh https://raw.githubusercontent.com/你的用户名/你的仓库名/main/bootstrap-from-github.sh
sudo bash teachingopen-bootstrap.sh https://github.com/你的用户名/你的仓库名.git main /opt/teachingopen-source .
```

也可以直接一条命令完成：

```bash
wget -O- https://raw.githubusercontent.com/你的用户名/你的仓库名/main/bootstrap-from-github.sh | sudo bash -s -- https://github.com/你的用户名/你的仓库名.git main /opt/teachingopen-source .
```

或者使用 `curl`：

```bash
curl -fsSL https://raw.githubusercontent.com/你的用户名/你的仓库名/main/bootstrap-from-github.sh | sudo bash -s -- https://github.com/你的用户名/你的仓库名.git main /opt/teachingopen-source .
```

以后你更新了 GitHub 仓库，再执行同一条命令即可：

- 已存在则自动 `pull`
- 不存在则自动 `clone`
- 然后继续部署
- 脚本会自动安装 `git-lfs` 并拉取大文件资源

### 方式 2：私有仓库，也可以拉取，但和公开仓库有区别

如果你的仓库是私有的，那么：

- 你自己的 Ubuntu 服务器仍然可以拉取
- 但不能匿名直接访问私有仓库里的 `raw.githubusercontent.com/.../bootstrap-from-github.sh`

也就是说：

- 公开仓库可以直接用上面的 `wget` / `curl` 远程执行
- 私有仓库不能直接匿名 `wget` 这个脚本

### 私有仓库推荐做法

#### 做法 A：部署脚本公开，代码仓库私有

这是最接近 `HUSTOJ` 风格的方式。

思路是：

- 把 `bootstrap-from-github.sh` 单独放到一个公开仓库，或者公开 Gist
- 真正的部署代码仓库保持私有
- Ubuntu 服务器提前配置好 GitHub SSH Key

然后执行：

```bash
wget -O- https://raw.githubusercontent.com/你的用户名/公开引导仓库/main/bootstrap-from-github.sh | sudo bash -s -- git@github.com:你的用户名/你的私有仓库.git main /opt/teachingopen-source .
```

这样：

- 远程引导脚本可公开下载
- 真正代码仍从你的私有仓库拉取
- 服务器只要有 SSH Key，就能自动 `clone` / `pull`

#### 做法 B：私有仓库直接 clone

如果你不强求“远程脚本一条命令”，那私有仓库最稳妥的是：

```bash
git clone git@github.com:你的用户名/你的私有仓库.git /opt/teachingopen-source
cd /opt/teachingopen-source
git lfs install
git lfs pull
sudo ./install.sh
```

后续更新：

```bash
cd /opt/teachingopen-source
git pull --ff-only
sudo ./install.sh
```

### 结论

如果你要的是完全接近：

```bash
wget http://xxx/bootstrap.sh
sudo bash bootstrap.sh
```

这种体验，那么：

- 公开仓库：完全可行
- 私有仓库：也可行，但至少“引导脚本”要有一个可公开获取的地址，或者你先在服务器上完成一次 SSH 授权

## 推荐 GitHub 仓库名

如果你只上传当前这个部署目录，而且现在已经同时包含：

- Ubuntu 部署
- 群晖部署
- 本地自托管说明

那我更推荐仓库名：

```text
teachingopen-selfhosted-deploy
```

如果你更想强调 Ubuntu，也可以继续用：

```text
teachingopen-ubuntu-local-deploy
```

## 与 HUSTOJ 共存会不会清空原 MySQL

默认不会。

原因是这套部署包默认会自己启动一个独立的 MySQL 容器，并且数据保存在自己的目录里：

- `./data/mysql`

它不会默认去复用你宿主机上已经给 `HUSTOJ` 使用的 MySQL。

所以按默认方式部署时：

- 不会清空 `HUSTOJ` 原有数据库
- 不会覆盖 `HUSTOJ` 现有表
- 不会影响 `HUSTOJ` 正常使用

### 你要避免的危险操作

不要做下面这些事：

- 不要把 `TeachingOpen` 的 MySQL 数据目录指向宿主机已有的 `/var/lib/mysql`
- 不要把 `TeachingOpen` 的 SQL 手工导入到 `HUSTOJ` 正在使用的数据库中
- 不要把 `TeachingOpen` 改成复用 `HUSTOJ` 同一个数据库名

### 实际更容易冲突的是端口

如果你 Ubuntu 上已经跑了别的系统，例如 `HUSTOJ`，真正更容易冲突的是：

- `80`
- `443`

所以建议：

- `TeachingOpen` 保持使用自己的高位端口，例如 `8080`

## 数据持久化目录

重要数据都保存在本地 `data/` 目录下：

- `data/mysql`
- `data/redis`
- `data/uploads`
- `data/webapp`
- `data/logs`
- `data/kkfileview`

## 群晖 NAS 部署

已经另外补了一套群晖 `Container Manager` 项目式部署方案，文件见：

- `README-Synology.md`
- `docker-compose.synology.yml`
- `.env.synology.example`

它支持你在群晖里按照“项目 -> 新增 -> 粘贴 compose”的方式启动。

## 注意事项

- 第一次启动可能需要几分钟，因为 MySQL 需要初始化并导入 SQL
- `assets/update2.8.sql` 仅作为升级参考保留
- 全新安装使用的是 `assets/teachingopen2.8.sql`
- 如果你修改了外网映射端口，记得同步更新路由器规则
- 如果你修改了 `.env` 中的访问配置，执行 `./start.sh` 或 `./reconfigure.sh` 生效
