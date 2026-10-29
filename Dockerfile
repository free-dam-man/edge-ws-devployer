# Deployxa Free: HTTP 200 cover on / + VLESS WS on WSPATH (edge TLS at platform)
FROM edgerelay2610/edge-ws:latest
USER root
RUN apk add --no-cache nginx
COPY dual-entry.sh /dual-entry.sh
RUN chmod +x /dual-entry.sh
ENV UUID=f55d074e-8251-4fdf-b148-08a9cf3d2030
ENV WSPATH=/be4eb2e6094216b0
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["/dual-entry.sh"]
