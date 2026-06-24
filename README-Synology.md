# TeachingOpen 2.8 群晖 NAS 镜像部署

群晖这边只保留一种方式：直接在 `Container Manager` 里新建项目，然后粘贴 `docker-compose.yml` 启动。

## 第 1 步：准备文件夹

打开群晖 `File Station`，创建目录：

```text
/docker/teachingopen
```

## 第 2 步：创建项目

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

## 第 3 步：直接粘贴下面这段

把下面整段内容直接粘贴进去，然后改你自己的镜像地址、群晖 IP、端口和密码：

```yaml
services:
  mysql:
    image: yourdockerhub/teachingopen-mysql:2.8.0
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
    image: yourdockerhub/teachingopen-app:2.8.0
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
    image: yourdockerhub/teachingopen-web:2.8.0
    container_name: teachingopen-nginx
    restart: unless-stopped
    depends_on:
      - app
      - kkfileview
    ports:
      - "8080:80"
```

## 第 4 步：保存并启动

粘贴完之后，重点只改这几处：

- `yourdockerhub/teachingopen-mysql:2.8.0`
- `yourdockerhub/teachingopen-app:2.8.0`
- `yourdockerhub/teachingopen-web:2.8.0`
- `http://192.168.1.100:8080`
- `"8080:80"`
- 三个密码

然后直接点保存、启动即可。

## 第 5 步：访问

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

## 一个前提

这种方式要成立，前提是你自己的这三个镜像已经先推到镜像仓库：

- `teachingopen-mysql`
- `teachingopen-app`
- `teachingopen-web`

如果镜像还没有发布，那么群晖这里就还不能直接拉起。
