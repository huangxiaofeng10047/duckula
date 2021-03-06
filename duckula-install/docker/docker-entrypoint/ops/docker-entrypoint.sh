#!/bin/sh

set -e

if [ "$1" = jetty.sh ]; then
	if ! command -v bash >/dev/null 2>&1 ; then
		cat >&2 <<- 'EOWARN'
			********************************************************************
			ERROR: bash not found. Use of jetty.sh requires bash.
			********************************************************************
		EOWARN
		exit 1
	fi
	cat >&2 <<- 'EOWARN'
		********************************************************************
		WARNING: Use of jetty.sh from this image is deprecated and may
			 be removed at some point in the future.

			 See the documentation for guidance on extending this image:
			 https://github.com/docker-library/docs/tree/master/jetty
		********************************************************************
	EOWARN
fi

if ! command -v -- "$1" >/dev/null 2>&1 ; then
	set -- java -jar "$JETTY_HOME/start.jar" "$@"
fi

: ${TMPDIR:=/tmp/jetty}
[ -d "$TMPDIR" ] || mkdir -p $TMPDIR 2>/dev/null

: ${JETTY_START:=$JETTY_BASE/jetty.start}

case "$JAVA_OPTIONS" in
	*-Djava.io.tmpdir=*) ;;
	*) JAVA_OPTIONS="-Djava.io.tmpdir=$TMPDIR $JAVA_OPTIONS" ;;
esac

if expr "$*" : 'java .*/start\.jar.*$' >/dev/null ; then
	# this is a command to run jetty

	# check if it is a terminating command
	for A in "$@" ; do
		case $A in
			--add-to-start* |\
			--create-files |\
			--create-startd |\
			--download |\
			--dry-run |\
			--exec-print |\
			--help |\
			--info |\
			--list-all-modules |\
			--list-classpath |\
			--list-config |\
			--list-modules* |\
			--stop |\
			--update-ini |\
			--version |\
			-v )\
			# It is a terminating command, so exec directly
			exec "$@"
		esac
	done

	if [ $(whoami) != "jetty" ]; then
		cat >&2 <<- EOWARN
			********************************************************************
			WARNING: User is $(whoami)
			         The user should be (re)set to 'jetty' in the Dockerfile
			********************************************************************
		EOWARN
	fi

	if [ -f $JETTY_START ] ; then
		if [ $JETTY_BASE/start.d -nt $JETTY_START ] ; then
			cat >&2 <<- EOWARN
			********************************************************************
			WARNING: The $JETTY_BASE/start.d directory has been modified since
			         the $JETTY_START files was generated. Either delete 
			         the $JETTY_START file or re-run 
			             /generate-jetty.start.sh 
			         from a Dockerfile
			********************************************************************
			EOWARN
		fi
		echo $(date +'%Y-%m-%d %H:%M:%S.000'):INFO:docker-entrypoint:jetty start from $JETTY_START
		set -- $(cat $JETTY_START)
	else
		# Do a jetty dry run to set the final command
		"$@" --dry-run > $JETTY_START
		if [ $(egrep -v '\\$' $JETTY_START | wc -l ) -gt 1 ] ; then
			# command was more than a dry-run
			cat $JETTY_START \
			| awk '/\\$/ { printf "%s", substr($0, 1, length($0)-1); next } 1' \
			| egrep -v '[^ ]*java .* org\.eclipse\.jetty\.xml\.XmlConfiguration '
			exit
		fi
		set -- $(sed 's/\\$//' $JETTY_START)
	fi
fi

if [ "${1##*/}" = java -a -n "$JAVA_OPTIONS" ] ; then
	java="$1"
	shift
	set -- "$java" $JAVA_OPTIONS "$@"
fi

echo "-------------------------begin--------------------------------------"
is_empty_dir(){ 
    return `ls -A $1|wc -w`
}
## 为版本升级，故意删除所有数据，重新配置
rm -fr /data/duckula-data/*
if is_empty_dir /data/duckula-data
then
    echo " /data/duckula-data 是空,系统会自动初始化此配置，task的容器需要挂载同样的卷"
    tar -xf /data/duckula-data.tar -C /data/ --strip-components=0
else
    echo " /data/duckula-data 不为空，使用加载卷的数据"    
fi
rm  -rf /data/duckula-data.tar


## 用户配置的配置项
rm -fr /opt/userconfig/lost+found
if is_empty_dir /opt/userconfig/
then
	echo "/opt/userconfig/ 不存在用户定义的卷"    
else
   echo "/opt/userconfig/ 存在用户定义的卷"
   # 防止把找不到目录错No such file or directory
   mkdir -p /data/duckula-data/conf/
   mkdir -p /data/duckula-data/conf/es/
   mkdir -p /data/duckula-data/conf/kafka/
   mkdir -p /data/duckula-data/conf/redis/
   #复制子目录，但是文件复制过去却是空的
   cp -rf /opt/userconfig/*   /data/duckula-data/conf
   #复制文件，为了修复上面命令的不足
   cp -f  /opt/userconfig/*.properties   /data/duckula-data/conf
fi



for path in \
		/data/duckula-data \
		/opt/duckula \
	; do
		chown -R jetty:jetty "$path"
done
echo "----------------------end-----------------------------------------"



exec "$@"
