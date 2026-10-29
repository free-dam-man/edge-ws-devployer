FROM edgerelay2610/edge-ws:latest
USER root
RUN apk add --no-cache nginx  && mkdir -p /tmp/nginx/client_body /tmp/nginx/proxy /tmp/nginx/fastcgi /tmp/nginx/uwsgi /tmp/nginx/scgi /tmp/nginx/logs  && chmod -R 777 /tmp/nginx
COPY dual-entry.sh /dual-entry.sh
RUN chmod +x /dual-entry.sh
ENV UUID=f55d074e-8251-4fdf-b148-08a9cf3d2030
ENV WSPATH=/be4eb2e6094216b0
ENV PORT=8080
EXPOSE 8080
# Prefer root; platforms that force non-root still work via /tmp paths
USER root
ENTRYPOINT ["/dual-entry.sh"]
