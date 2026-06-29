# TeachingOpen 2.8 自托管部署

这个仓库只做两件事：

1. Ubuntu 一键部署
2. 群晖 / 威联通 NAS 容器部署

不依赖宝塔，数据默认保存在你自己的机器里。

## 方式 1：Ubuntu 一键部署

直接执行这一条命令：

```bash
wget -O- https://raw.githubusercontent.com/chardlink/teachingopen-deploy/main/bootstrap-from-github.sh | sudo bash -s -- https://github.com/chardlink/teachingopen-deploy.git main /opt/teachingopen-source .
```

首次部署会自动完成：

- 安装 `git`
- 安装 `git-lfs`
- 拉取仓库和大文件
- 安装 `Docker`
- 安装 `docker compose` / `docker-compose`
- 自动创建 `.env`
- 启动全部容器

当前默认值：

```text
WEB_PORT=1168
APP_DEBUG_PORT=18080
PUBLIC_BASE_URL=http://服务器IP:1168
```

说明：

- 当前 Ubuntu 方案是 Docker 容器化部署，不是宿主机原生直装
- 这样做是为了尽量不碰你宿主机现有的 MySQL、Redis 和 HUSTOJ 数据
- 部署过程中不再中途让你输入端口
- 部署完成后会先显示当前访问地址，再让你选择是否进入端口配置

部署完成后你会看到：

```text
当前访问地址：
http://你的服务器IP:1168

后续操作：
1. 立即配置端口和 PUBLIC_BASE_URL
2. 直接退出
```

如果你选择 `1`，脚本会让你重新填写端口和 `PUBLIC_BASE_URL`，然后自动重启容器。

默认访问示例：

```text
http://服务器IP:1168
```

如果第一次安装中途失败，不需要删目录，直接重新执行：

```bash
cd /opt/teachingopen-source
sudo ./install.sh
```

如果后续只想更新：

```bash
cd /opt/teachingopen-source
sudo ./update.sh
```

如果后续只想改端口或外网入口：

```bash
cd /opt/teachingopen-source
sudo ./reconfigure.sh
```

常用查看命令：

```bash
cd /opt/teachingopen-source
./status.sh
./logs.sh
```

## 方式 2：群晖 / 威联通 NAS 容器部署

这一套和 Ubuntu 一键脚本是分开的。

- Ubuntu：运行一键部署脚本
- NAS：在容器管理界面里直接粘贴 `docker-compose.yml`

### 第 1 步：准备目录

在 NAS 里新建目录：

```text
/docker/teachingopen
```

### 第 2 步：新建项目

群晖：

- 打开 `Container Manager`
- 进入 `项目`
- 点击 `新增`

威联通：

- 打开 `Container Station`
- 新建 Compose 项目

项目名：

```text
teachingopen
```

路径：

```text
/docker/teachingopen
```

来源：

```text
创建 docker-compose.yml
```

### 第 3 步：直接复制下面内容

下面这段内容可以直接用，不需要额外改结构。  
你只需要改你自己的 NAS IP、端口和密码。

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
    volumes:
      - ./data/uploads:/data/uploads:ro
```

### 第 4 步：保存并启动

重点只改这几处：

- `http://192.168.1.100:8080`
- `"8080:80"`
- 三个密码

如果你的 NAS 端口冲突，就把 `8080` 改成你自己的端口，同时把上面的 URL 也一起改掉。

### 第 5 步：访问

```text
http://你的NAS-IP:8080
```

## 默认测试账号

- `admin`
- `teacher`
- `student`

默认密码：

- `123456`
