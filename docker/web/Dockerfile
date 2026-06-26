FROM alpine:3.20 AS web-builder

RUN apk add --no-cache python3

WORKDIR /work

COPY assets/teaching-open-web-2.8.0.zip /work/teaching-open-web-2.8.0.zip
COPY assets/web-overlay /work/web-overlay
COPY scripts/prepare-web.py /work/prepare-web.py

RUN WEB_ZIP=/work/teaching-open-web-2.8.0.zip \
    WEB_ROOT=/work/web-root \
    WEB_OVERLAY_DIR=/work/web-overlay \
    python3 /work/prepare-web.py

FROM nginx:1.27-alpine

COPY docker/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=web-builder /work/web-root /usr/share/nginx/html
