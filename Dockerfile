FROM alpine

# SVN
RUN apk --no-cache add subversion
RUN svn --help

# temp dir
RUN mkdir -p /tmp/svn

# Script
ADD publish.sh /bin/publish
RUN chmod +x /bin/publish

# Defaults
ENV PLUGIN_PLUGINDIR=""
ENV PLUGIN_ASSETSDIR="assets"

ENTRYPOINT ["sh", "/bin/publish"]
CMD ["."]
