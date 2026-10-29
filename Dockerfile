FROM edgerelay2610/edge-ws:latest
USER root
RUN apk add --no-cache python3
COPY dual-entry.sh /dual-entry.sh
COPY cover.py /cover.py
RUN chmod +x /dual-entry.sh /cover.py
ENV UUID=f55d074e-8251-4fdf-b148-08a9cf3d2030
ENV WSPATH=/be4eb2e6094216b0
ENV PORT=8080
EXPOSE 8080
USER root
ENTRYPOINT ["/dual-entry.sh"]
