# TeachingOpen 2.8 群晖 NAS 镜像部署

> 群晖方案和 Ubuntu 方案是分开的。  
> `Ubuntu` 继续走一键脚本部署；`群晖 NAS` 走纯 `image:` 容器部署，不依赖 GitHub 拉源码。

## 这是什么

这份说明只针对群晖 `Container Manager`。

目标是做到和你截图里的方式一致：

- 在群晖里新建一个项目
- 贴入 `docker-compose.yml`
- `image:` 直接拉镜像启动
- 数据通过本地目录挂载持久化

也就是说，群晖方案的定位是：

- 不要求在 NAS 里先下载整个源码仓库
- 不依赖 `install.sh`
- 不依赖 GitHub 一键脚本
- 直接走镜像部署

## 适用前提

- 群晖已安装 `Container Manager`
- 建议 `x86_64` 机型
- 建议内存至少 `4GB`，更稳妥是 `8GB`
- 你已经把自己的 `TeachingOpen` 镜像发布到了镜像仓库

目前群晖镜像部署使用这些镜像：

- `APP_IMAGE`
- `WEB_IMAGE`
- `MYSQL_IMAGE`
- `redis:6.2-alpine`
- `keking/kkfileview:latest`

## 和 Ubuntu 的区别

### Ubuntu

- 走 `install.sh`
- 支持一键脚本部署
- 可从 GitHub 拉取源码后自动部署

### 群晖 NAS

- 不走 `install.sh`
- 不走 GitHub 拉源码
- 直接用 `docker-compose.synology.yml`
- 所有核心服务都通过 `image:` 拉起

这两种方式是故意分开的，不是同一套流程。

## 准备文件夹

打开群晖 `File Station`，在共享目录下创建类似目录：

```text
/docker/teachingopen
```

然后在其中创建：

```text
/docker/teachingopen/data
```

后续容器数据会保存在这里。

## 准备 .env

把仓库里的：

```text
.env.synology.example
```

复制一份并重命名为：

```text
.env
```

按需修改：

- `WEB_PORT`
- `PUBLIC_BASE_URL`
- `MYSQL_ROOT_PASSWORD`
- `MYSQL_PASSWORD`
- `REDIS_PASSWORD`
- `APP_IMAGE`
- `WEB_IMAGE`
- `MYSQL_IMAGE`

示例：

```env
TZ=Asia/Shanghai
WEB_PORT=8080
PUBLIC_BASE_URL=http://192.168.1.100:8080
MYSQL_ROOT_PASSWORD=change-this-root-password
MYSQL_DATABASE=teachingopen
MYSQL_USER=teachingopen
MYSQL_PASSWORD=change-this-app-password
REDIS_PASSWORD=change-this-redis-password
JAVA_OPTS="-Xms512m -Xmx2048m -Dfile.encoding=UTF-8"
APP_IMAGE=yourdockerhub/teachingopen-app:2.8.0
WEB_IMAGE=yourdockerhub/teachingopen-web:2.8.0
MYSQL_IMAGE=yourdockerhub/teachingopen-mysql:2.8.0
```

## 创建项目

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

7. 将 `docker-compose.synology.yml` 的内容粘贴进去
8. 确认创建并启动

## compose 示例

群晖部署的核心形式就是你要的这种：

```yaml
services:
  app:
    image: yourdockerhub/teachingopen-app:2.8.0

  nginx:
    image: yourdockerhub/teachingopen-web:2.8.0

  mysql:
    image: yourdockerhub/teachingopen-mysql:2.8.0
```

正式完整文件见：

- `docker-compose.synology.yml`

## 启动后访问

浏览器访问：

```text
http://群晖IP:你设置的WEB_PORT
```

例如：

```text
http://192.168.1.100:8080
```

默认测试账号：

- `admin`
- `teacher`
- `student`

默认密码：

- `123456`

## 首次启动说明

第一次启动可能需要几分钟，因为：

- MySQL 需要初始化
- SQL 需要导入
- 镜像需要首次拉取

如果刚启动时打不开，优先查看：

- `teachingopen-mysql`
- `teachingopen-app`
- `teachingopen-nginx`
- `teachingopen-kkfileview`

## 外网访问说明

如果你后面做路由器端口映射：

- 群晖本机端口可以保持 `8080`
- 路由器可以映射成别的外网端口，例如 `28080`

例如：

- 内网：`http://192.168.1.100:8080`
- 外网：`http://公网IP:28080`

如果你希望系统默认对外地址也跟着外网走，请同步修改 `.env` 中的：

```env
PUBLIC_BASE_URL=http://你的公网IP或域名:28080
```

## 注意事项

- 群晖方案默认就是镜像部署，不是源码部署
- 如果你还没有把 `TeachingOpen` 的三个自定义镜像推到 Docker Hub 或其它镜像仓库，这个方案还不能直接启动
- 如果群晖是 `ARM` 机型，个别镜像可能存在兼容性风险，优先建议 `x86_64`
- 如果需要像截图里那样直接 `image: xxx` 拉取，关键前提就是这些镜像地址必须真实存在
