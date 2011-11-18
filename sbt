#!/bin/sh

if [ -z "$SBT_OPTS" ]; then
	SBT_OPTS="-Xmx4096m -Xms4096m -XX:NewSize=768m -XX:MaxPermSize=1024m";
fi
if [ -z "$TUMBLR_NO_REPO" ]; then
        if [ -z "$TUMBLR_REPO" ]; then
                export TUMBLR_REPO="http://repo.tumblr.net:8081/nexus/content/groups/public/"
                if [ -z "$SBT_BOOT_PROPERTIES" ]; then
	                SBT_BOOT_PROPERTIES="-Dsbt.boot.properties=`dirname $0`/project/sbt.boot.properties"
                fi
                if [ -z "$TUMBLR_PUBLISH_URL" ]; then
                        export TUMBLR_PUBLISH_URL="http://repo.tumblr.net:8081/nexus/content/repositories"
                fi
        fi
fi
if [ -z "$SBT_BOOT_PROPERTIES" ]; then
  SBT_BOOT_PROPERTIES=""
fi
java ${SBT_OPTS} ${SBT_BOOT_PROPERTIES} -Dactors.minPoolSize=128 -Dactors.corePoolSize=256 -Dactors.maxPoolSize=512 -jar `dirname $0`/lib/sbt-launch.jar "$@"