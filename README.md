# TeachingOpen 2.8 自托管部署

这个仓库只做两件事：

1. `Ubuntu` 一键脚本部署
2. `群晖 NAS` 容器镜像部署

不再依赖宝塔，数据默认保存在你自己的机器上。

## 方式 1：Ubuntu 一键脚本部署

直接执行这一条命令：

```bash
wget -O- https://raw.githubusercontent.com/chardlink/teachingopen-deploy/main/bootstrap-from-github.sh | sudo bash -s -- https://github.com/chardlink/teachingopen-deploy.git main /opt/teachingopen-source .
```

脚本会自动完成：

- 安装 `git`
- 安装 `git-lfs`
- 下载仓库
- 安装 `Docker`（优先官方源，失败自动回退到 Ubuntu 软件源）
- 创建 `.env`
- 提示你填写端口和 `PUBLIC_BASE_URL`
- 自动启动全部容器

如果你的网络访问 `download.docker.com` 不稳定，不需要手动清理再重来。
现在脚本会先尝试官方安装方式，失败后自动改走 Ubuntu 自带软件源继续安装。

如果后续要改端口或外网入口，执行：

```bash
cd /opt/teachingopen-source
./reconfigure.sh
```

如果 Docker Hub 拉镜像失败，先执行：

```bash
cd /opt/teachingopen-source
sudo ./configure-docker-mirror.sh
```

默认访问地址：

```text
http://服务器IP:8080
```

## 方式 2：群晖 NAS 容器镜像部署

这套方式和 Ubuntu 是分开的。

群晖这边不是跑一键脚本，而是直接在 `Container Manager` 里面新建项目，然后粘贴 `docker-compose.yml`。

### 第 1 步：准备文件夹

打开群晖 `File Station`，创建目录：

```text
/docker/teachingopen
```

### 第 2 步：创建项目

1. 打开 `Container Manager`
2. 进入 `项目`
3. 点击 `新增`
4. 项目名称填写：

```text
teachingopen
```

5. 路径选择：

```text
/docker/teachingopen
```

6. 来源选择：

```text
创建 docker-compose.yml
```

### 第 3 步：直接复制下面这段内容

把下面整段内容直接粘贴进去，然后只改你自己的镜像地址、群晖 IP 和端口即可：

```yaml
services:
  mysql:
    image: chardchao/teachingopen-mysql:2.8.0
    container_name: teachingopen-mysql
    restart: unless-stopped
    environment:
      TZ: Asia/Shanghai
      MYSQL_ROOT_PASSWORD: change-this-root-password
      MYSQL_DATABASE: teachingopen
      MYSQL_USER: teachingopen
      MYSQL_PASSWORD: change-this-app-password
    volumes:
      - ./data/mysql:/var/lib/mysql

  redis:
    image: redis:6.2-alpine
    container_name: teachingopen-redis
    restart: unless-stopped
    command: >
      sh -c 'redis-server --appendonly yes --requirepass "$${REDIS_PASSWORD}" --save 60 1'
    environment:
      TZ: Asia/Shanghai
      REDIS_PASSWORD: change-this-redis-password
    volumes:
      - ./data/redis:/data

  app:
    image: chardchao/teachingopen-app:2.8.0
    container_name: teachingopen-app
    restart: unless-stopped
    depends_on:
      - mysql
      - redis
    environment:
      TZ: Asia/Shanghai
      JAVA_OPTS: -Xms512m -Xmx2048m -Dfile.encoding=UTF-8
      TEACHING_DOMAIN: http://192.168.1.100:8080
      FILE_VIEW_DOMAIN: http://192.168.1.100:8080/preview
      DB_HOST: mysql
      DB_PORT: 3306
      DB_NAME: teachingopen
      DB_USER: teachingopen
      DB_PASS: change-this-app-password
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: change-this-redis-password
    volumes:
      - ./data/uploads:/data/uploads
      - ./data/webapp:/data/webapp
      - ./data/logs:/data/logs

  kkfileview:
    image: keking/kkfileview:latest
    container_name: teachingopen-kkfileview
    restart: unless-stopped
    environment:
      TZ: Asia/Shanghai
    volumes:
      - ./data/kkfileview:/opt/kkFileView

  nginx:
    image: chardchao/teachingopen-web:2.8.0
    container_name: teachingopen-nginx
    restart: unless-stopped
    depends_on:
      - app
      - kkfileview
    ports:
      - "8080:80"
```

### 第 4 步：保存并启动

粘贴完之后，重点只改这几处：

- `chardchao/teachingopen-mysql:2.8.0`
- `chardchao/teachingopen-app:2.8.0`
- `chardchao/teachingopen-web:2.8.0`
- `http://192.168.1.100:8080`
- `"8080:80"`
- 三个密码

然后直接点保存、启动即可。

### 第 5 步：访问

浏览器访问：

```text
http://群晖IP:8080
```

默认测试账号：

- `admin`
- `teacher`
- `student`

默认密码：

- `123456`

## 一个前提要说清楚

群晖这种“直接 `image:` 部署”的前提是：

你自己的这三个镜像必须已经先发布到镜像仓库：

- `teachingopen-mysql`
- `teachingopen-app`
- `teachingopen-web`

如果镜像还没有推送到 Docker Hub 或其它镜像仓库，那么群晖这条方式还不能直接拉起。

## 如果你想自己发布镜像

仓库里已经准备好了镜像构建文件：

- `docker/app/Dockerfile`
- `docker/web/Dockerfile`
- `docker/mysql/Dockerfile`
- `docker-build-images.sh`
- `docker-push-images.sh`

本地构建：

```bash
IMAGE_NAMESPACE=chardchao IMAGE_TAG=2.8.0 ./docker-build-images.sh
```

登录并推送：

```bash
docker login
IMAGE_NAMESPACE=chardchao IMAGE_TAG=2.8.0 ./docker-push-images.sh
```

## Ubuntu 部署会做什么

`install.sh` 会自动完成这些事情：

- 安装基础依赖 `ca-certificates`、`curl`、`unzip`
- 安装 `Docker`
- 安装 `docker compose plugin`
- 创建或读取 `.env`
- 显示默认端口和访问地址
- 询问你是否修改端口和 `PUBLIC_BASE_URL`
- 自动解压并修补前端静态包
- 拉取镜像并启动容器

`bootstrap-from-github.sh` 额外会自动完成：

- 安装 `git`
- 安装 `git-lfs`
- 仓库不存在时执行 `clone`
- 仓库已存在时执行 `fetch + pull`
- 自动拉取 `Git LFS` 大文件
- 自动进入部署目录并执行 `install.sh`

## 部署架构

Ubuntu 方案会启动以下服务：

- `mysql:5.7`
- `redis:6.2-alpine`
- `eclipse-temurin:8-jre`
- `nginx:1.27-alpine`
- `keking/kkfileview:latest`

群晖方案在此基础上额外包含：

- `web-prep`

`web-prep` 用于自动解压并修补前端静态包，避免你在群晖里手动处理前端文件。

## 为什么不是 JSON / YAML 存储

当前 `TeachingOpen 2.8` 是已经编译好的 Java 程序，后端本身硬依赖：

- `MySQL`
- `Redis`

所以它不能直接改成纯 `JSON` 或纯 `YAML` 持久化，除非重写后端逻辑。

但如果你的目标是“数据不要放第三方服务、只放在自己机器上”，这套方案已经满足，因为：

- 数据库在你自己的 `MySQL` 容器里
- 缓存在你自己的 `Redis` 容器里
- 上传文件在你自己的本地目录里

## 仓库结构

```text
.
├─ assets/                     官方 jar、前端 zip、SQL
├─ config/                     后端挂载配置
├─ docker/                     Nginx / MySQL 配置
├─ scripts/                    辅助脚本
├─ data/                       持久化数据目录
├─ runtime/web-root/           解压后的前端静态文件
├─ .env.example                Ubuntu 环境变量示例
├─ .env.synology.example       群晖镜像部署环境变量示例
├─ docker-compose.yml          Ubuntu / 通用 Compose
├─ docker-compose.synology.yml 群晖项目式镜像 Compose
├─ install.sh                  Ubuntu 首次部署脚本
├─ reconfigure.sh              修改端口 / PUBLIC_BASE_URL
├─ configure-docker-mirror.sh  配置 Docker 镜像加速
├─ docker-build-images.sh      构建纯 image 部署镜像
├─ docker-push-images.sh       推送纯 image 部署镜像
├─ bootstrap-from-github.sh    GitHub 拉取并部署脚本
└─ README-Synology.md          群晖部署说明
```

## 数据保存位置

重要数据默认保存在本地 `data/` 目录：

- `data/mysql`
- `data/redis`
- `data/uploads`
- `data/webapp`
- `data/logs`
- `data/kkfileview`

这意味着：

- 删除容器不会直接丢数据
- 迁移服务器时可以连同目录一起迁移
- 备份时有明确的数据位置

## 配置说明

首次部署时，`.env` 会自动生成。你也可以参考：

- `.env.example`
- `.env.synology.example`

常用字段如下：

| 变量 | 作用 |
| --- | --- |
| `WEB_PORT` | Nginx 对外监听端口 |
| `APP_DEBUG_PORT` | 后端调试端口，仅绑定到 `127.0.0.1` |
| `PUBLIC_BASE_URL` | 系统默认对外地址，不是监听地址 |
| `MYSQL_ROOT_PASSWORD` | MySQL root 密码 |
| `MYSQL_DATABASE` | TeachingOpen 使用的数据库名 |
| `MYSQL_USER` | TeachingOpen 使用的数据库用户 |
| `MYSQL_PASSWORD` | TeachingOpen 使用的数据库密码 |
| `REDIS_PASSWORD` | Redis 密码 |
| `JAVA_OPTS` | Java 内存参数 |

默认示例：

```env
TZ=Asia/Shanghai
WEB_PORT=8080
APP_DEBUG_PORT=18080
PUBLIC_BASE_URL=http://127.0.0.1:8080
MYSQL_ROOT_PASSWORD=change-this-root-password
MYSQL_DATABASE=teachingopen
MYSQL_USER=teachingopen
MYSQL_PASSWORD=change-this-app-password
REDIS_PASSWORD=change-this-redis-password
JAVA_OPTS="-Xms512m -Xmx2048m -Dfile.encoding=UTF-8"
```

## 首次部署时会提示什么

首次执行 `install.sh` 时，脚本会显示默认值：

- `WEB_PORT=8080`
- `APP_DEBUG_PORT=18080`
- `PUBLIC_BASE_URL=http://服务器IP:8080`

然后你可以：

- 直接使用默认值
- 改成自己的端口和访问地址
- 先生成 `.env`，再手动修改后继续

如果目录里已经有 `.env`，脚本会先显示当前配置，并询问你是否先手动修改。

## 访问方式

前端入口：

```text
http://服务器IP:WEB_PORT
```

后端调试入口：

```text
http://127.0.0.1:APP_DEBUG_PORT
```

例如默认配置下：

- 前端：`http://192.168.1.50:8080`
- 后端调试：`http://127.0.0.1:18080`

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

查看状态：

```bash
./status.sh
```

查看日志：

```bash
./logs.sh
./logs.sh app
./logs.sh mysql
./logs.sh nginx
```

备份：

```bash
./backup.sh
```

`backup.sh` 会生成：

- MySQL 导出文件
- `uploads` 打包文件
- 当前 `.env`

备份目录示例：

```text
backups/20260624-120000/
```

## 后续修改端口或外网入口

不需要重新部署。

如果你后续想修改：

- 本机服务端口 `WEB_PORT`
- 本机调试端口 `APP_DEBUG_PORT`
- 默认对外地址 `PUBLIC_BASE_URL`

执行：

```bash
./reconfigure.sh
```

这个脚本会：

- 显示当前配置
- 询问新的本机端口
- 询问新的外网协议、主机和端口
- 自动写回 `.env`
- 自动执行一次 `stop` 和 `start`

## 网络访问说明

`PUBLIC_BASE_URL` 不是容器监听地址，它表示系统默认认为的“对外入口地址”。

可以这样理解：

- `WEB_PORT`
  - 服务器真正监听的端口
- `PUBLIC_BASE_URL`
  - 系统生成链接、文件预览、部分跳转时默认使用的地址

### 内外网同时访问

完全可行。

例如：

- 服务器内网 IP：`192.168.1.50`
- 本机监听端口：`8080`
- 路由器外网映射：`28080 -> 8080`

那么：

- 内网访问：`http://192.168.1.50:8080`
- 外网访问：`http://公网IP:28080`

### 内外网端口不一致

完全可行，不需要强行占用 `80` 端口。

例如：

- 本机：`8080`
- 外网：`28080 -> 8080`

这是标准做法。

### 动态公网 IP

不要求固定公网 IP。

更推荐的做法是使用 `DDNS`，例如：

```env
PUBLIC_BASE_URL=http://你的DDNS域名:28080
```

这样公网 IP 变化时，不需要每次都改成新的 IP。

### 如果主要是内网使用

你也可以把 `PUBLIC_BASE_URL` 写成内网地址：

```env
PUBLIC_BASE_URL=http://192.168.1.50:8080
```

这样内网使用最稳，但要注意：

- 公网用户手动访问公网地址仍然可以打开页面
- 某些绝对链接、文件预览、跳转可能仍然回到内网地址

如果你明确要兼顾公网访问，最好还是写：

- 公网 IP
- 或 DDNS 域名

## 与 HUSTOJ 共存

默认不会影响原有 `HUSTOJ` 数据。

原因是这套部署包会自己启动独立的 `MySQL` 容器，并且数据只写到：

```text
./data/mysql
```

它不会默认复用你宿主机里已经给 `HUSTOJ` 使用的 MySQL 数据目录。

默认部署下：

- 不会清空 `HUSTOJ` 的数据库
- 不会覆盖 `HUSTOJ` 的表
- 不会影响 `HUSTOJ` 原有服务

真正更容易冲突的通常是端口，例如：

- `80`
- `443`

所以更建议 `TeachingOpen` 使用自己的高位端口，例如 `8080`。

## GitHub 与 Git LFS 说明

仓库中的两个大文件：

- `assets/teaching-open-2.8.0.jar`
- `assets/teaching-open-web-2.8.0.zip`

已经通过 `.gitattributes` 走 `Git LFS` 管理，因为它们超过了普通 GitHub 单文件限制。

如果你是手动 `git clone`，建议执行：

```bash
git lfs install
git lfs pull
```

如果你走的是：

- `bootstrap-from-github.sh`

则脚本会自动处理 `Git LFS`，不需要你手动再拉一次。

如果你后面把仓库从公开改成私有，需要注意：

- 服务器上已拉下来的代码不会受影响
- 后续再 `git pull` 时，需要给服务器配置 GitHub 认证
- 匿名 `wget raw.githubusercontent.com/...` 将不再可用

## Docker Hub 拉取失败怎么办

如果你在 Ubuntu 上看到类似报错：

```text
failed to resolve reference "docker.io/library/nginx:1.27-alpine"
read: connection reset by peer
```

这通常不是脚本卡住，而是：

- 代码已经拉下来了
- `.env` 已经生成了
- 失败点出在 `docker compose pull`

常见原因：

- Docker Hub 网络不稳定
- Docker daemon 没走代理
- Docker daemon 没配镜像加速
- IPv6 到 `registry-1.docker.io` 的连接被重置

你可以先执行：

```bash
cd /opt/teachingopen-source
sudo ./configure-docker-mirror.sh
```

这个脚本现在同时支持两种方式：

- 配置 `registry-mirrors`
- 配置 Docker daemon 代理

如果你的 Ubuntu 本机本身就能通过代理访问外网，更推荐直接把 Docker daemon 也接入同一个代理，例如：

```bash
cd /opt/teachingopen-source
sudo DOCKER_HTTP_PROXY="http://127.0.0.1:7890" DOCKER_HTTPS_PROXY="http://127.0.0.1:7890" DOCKER_NO_PROXY="localhost,127.0.0.1" ./configure-docker-mirror.sh
```

如果你已经有可用的 Docker 镜像加速地址，也可以直接一条命令写入：

```bash
cd /opt/teachingopen-source
sudo REGISTRY_MIRRORS="https://你的镜像加速地址" ./configure-docker-mirror.sh
```

脚本会自动：

- 备份 `/etc/docker/daemon.json`
- 写入 `registry-mirrors` 和/或 `proxies`
- 重启 Docker

然后重新执行：

```bash
cd /opt/teachingopen-source
sudo ./install.sh
```

如果只是想继续启动，也可以执行：

```bash
cd /opt/teachingopen-source
./start.sh
```

## 群晖 NAS 部署

群晖已经单独提供部署说明，见：

- `README-Synology.md`
- `docker-compose.synology.yml`
- `.env.synology.example`

这套方案适合你在群晖 `Container Manager` 中按“项目 -> 新增 -> 粘贴 Compose”方式启动。

群晖方案与 Ubuntu 方案的主要区别是：

- 不依赖 `apt-get`
- 使用额外的 `web-prep` 容器处理前端静态资源

如果你主要部署在群晖，直接优先看 `README-Synology.md` 即可。

## 首次启动与排错

第一次启动可能需要几分钟，因为需要完成：

- MySQL 初始化
- SQL 导入
- 前端静态包解压
- 容器镜像首次拉取

如果刚启动后打不开，优先检查：

```bash
./status.sh
./logs.sh mysql
./logs.sh app
./logs.sh nginx
```

重点排查：

- `WEB_PORT` 是否被其它服务占用
- 路由器映射端口是否填错
- `.env` 中的 `PUBLIC_BASE_URL` 是否明显写错
- 前端文件是否成功生成到 `runtime/web-root/`

补充说明：

- 全新安装使用的是 `assets/teachingopen2.8.sql`
- `assets/update2.8.sql` 仅作为升级参考保留
