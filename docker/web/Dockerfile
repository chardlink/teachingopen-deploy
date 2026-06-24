FROM alpine:3.20 AS web-builder

RUN apk add --no-cache unzip

WORKDIR /work

COPY assets/teaching-open-web-2.8.0.zip /work/teaching-open-web-2.8.0.zip

RUN mkdir -p /work/web-root \
    && unzip -oq /work/teaching-open-web-2.8.0.zip -d /work/web-root \
    && sed -i "s|<script async src=//api.paas.plus/js/errlog.js></script>||g" /work/web-root/index.html \
    && sed -i "s|window._CONFIG\\['onlinePreviewDomainURL'\\] = 'http://fileview.jeecg.com/onlinePreview'|window._CONFIG['onlinePreviewDomainURL'] = window._CONFIG['webURL'] + '/preview/onlinePreview'|g" /work/web-root/index.html

FROM nginx:1.27-alpine

COPY docker/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=web-builder /work/web-root /usr/share/nginx/html
