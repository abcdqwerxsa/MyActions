# 使用最轻量级的 alpine 镜像
FROM nginx:alpine

# 向默认首页写入一点自定义内容，方便区分不同的容器实例
RUN echo "<h1>Docker Test Page - Success!</h1>" > /usr/share/nginx/html/index.html

# 暴露 80 端口
EXPOSE 80
