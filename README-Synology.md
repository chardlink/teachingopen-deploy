# TeachingOpen 2.8 群晖 NAS 一键容器部署

这套文件支持群晖 `Container Manager` 直接创建项目，方式尽量靠近你截图里的“新建项目 -> 粘贴 compose -> 启动”。

## 适用前提

- 群晖已安装 `Container Manager`
- 建议 `x86_64` 机型
- 建议内存至少 `4GB`，更稳妥是 `8GB`
- 你已经把当前整个 `TeachingOpen2.8-ubuntu-local-deploy` 目录放到了群晖某个共享文件夹里

## 推荐目录

建议在群晖 `File Station` 中准备类似目录：

```text
/docker/teachingopen-ubuntu-local-deploy
```

把当前整个部署目录里的所有文件都上传进去，不要只传单个 compose 文件。

## 先准备 .env

在群晖里把：

```text
.env.synology.example
```

复制一份并重命名为：

```text
.env
```

然后按需修改：

- `WEB_PORT`
  - 群晖对外访问端口，例如 `8080`
- `PUBLIC_BASE_URL`
  - 内网访问可写成 `http://群晖IP:8080`
  - 如果你后面走公网映射，也可以写成 `http://你的外网地址:映射端口`
- `MYSQL_ROOT_PASSWORD`
- `MYSQL_PASSWORD`
- `REDIS_PASSWORD`

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
```

## 方式 1：群晖界面导入项目

1. 打开 `Container Manager`
2. 进入 `项目`
3. 点击 `新增`
4. 项目名称填写：

```text
teachingopen
```

5. 路径选择你刚才上传的目录，例如：

```text
/docker/teachingopen-ubuntu-local-deploy
```

6. 来源选择：

```text
创建 docker-compose.yml
```

7. 将 `docker-compose.synology.yml` 的内容粘贴进去
8. 确认创建并启动

## 方式 2：直接使用仓库里的 compose 文件

如果你的群晖版本支持“从文件加载 compose”，直接选用：

```text
docker-compose.synology.yml
```

项目路径仍然选择整个部署目录。

## 这套群晖部署会自动做什么

- 初始化 `MySQL`
- 初始化 `Redis`
- 启动 `TeachingOpen` 后端
- 启动 `Nginx`
- 启动 `kkFileView`
- 自动解压并修补前端静态包

也就是说，你不需要再手动解压前端 zip。

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
- 前端静态包需要自动解压

如果刚启动时打不开，先在 `Container Manager` 里看各容器日志，重点看：

- `teachingopen-mysql`
- `teachingopen-app`
- `teachingopen-nginx`
- `teachingopen-web-prep`

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

- 这套方案比 Ubuntu 脚本部署更适合群晖，因为它不依赖 `apt-get`
- 如果群晖是 `ARM` 机型，个别镜像可能存在兼容性风险，优先建议 `x86_64`
- 如果你是通过 GitHub 同步这个目录到群晖，也可以继续用这套文件，不冲突
