#!/bin/bash
################################################################################
# chroot.sh - kinesis (mail@kinesis.me)                                        #
# Objective: complete and concisive method of chrooting processes in RHEL      #
################################################################################

# Extra binaries, config files, etc that are useful for a jail.
EXTRAS="/bin/rm /bin/ps /bin/su /bin/mv /bin/mkdir /bin/touch /bin/cat /usr/bin/whoami /usr/bin/id \
	/bin/bash /bin/sh /bin/ls /dev/console /dev/null /dev/zero /dev/ptmx /dev/tty /dev/random \
	/dev/urandom /etc/hosts /etc/resolv.conf /etc/nsswitch.conf /etc/localtime /etc/services \
	/etc/protocols /sbin/nologin /usr/bin/groups /bin/grep /bin/chmod /bin/stty /bin/sed \ 
	/bin/hostname /bin/chown /bin/tar /bin/gzip /bin/cp /usr/bin/expr /usr/bin/dirname /bin/date"

function print_usage() {
		echo "chroot.sh by kinesis (mail@kinesis.me)
			Usage: $0 <arg> <chroot path>

			Valid arguments are:
			  --mysql		- Jails MySQL
			  --nginx		- Jails nginx
			  --php-fpm		- Jails php-fpm
			  --php			- Jails php (??? experimental)
			  --httpd		- Jails httpd(and possibly PHP or Tomcat)
			  --enter		- Enters specified jail"
		exit 2
}

function enter() {
	if [ -d "$1" ]; then
		echo "Entering $1: "
		[  "$(cat /proc/mounts | grep $1/sys)" ] || mount --bind /sys $1/sys
 		[  "$(cat /proc/mounts | grep $1/proc)" ] || mount -t proc none $1/proc
		chroot $1 /bin/bash
	else
		echo "Failed to enter $1."
	fi
}
function prep() {
	[ ! -d "$1/dev" ] && (mkdir -p $1/dev;chmod 755 $1/dev; \
				  ln -s /proc/self/fd $1/dev/; ln -s /proc/self/fd/0 $1/dev/stdin; \
				  ln -s /proc/self/fd/1 $1/dev/stdout; ln -s /proc/self/fd/2 $1/dev/stderr; \
				  ln -s /proc/kcore $1/dev/core;)

	[ ! -d "$1/proc" ] && mkdir $1/proc;chmod 555 $1/proc
	[ ! -d "$1/sys" ] && mkdir $1/sys;chmod 755 $1/sys
	[ ! -d "$1/tmp" ] && mkdir $1/tmp;chmod 777 $1/tmp;chmod +t $1/tmp
	
	# to do : Use existing system gid (check) or claim 91-95
	touch $1/etc/{passwd,group}
	cat <<-EOF>$1/etc/passwd
	root:x:0:0:root:/:/sbin/nologin
	nginx:x:91:91:nginx:/tmp:/sbin/nologin
	www-data:x:92:92:www-data:/tmp:/sbin/nologin
	mysql:x:93:93:mysql:/tmp:/sbin/nologin
	httpd:x:94:94:httpd:/tmp:/sbin/nologin
	nobody:x:99:99:nobody:/tmp:/sbin/nologin
	EOF

	cat <<-EOF>$1/etc/group
	root:x:0:root
	nginx:x:91:nginx
	www-data:x:92:www-data
	mysql:x:93:mysql
	httpd:x:94:94:httpd
	nobody:x:99:99:nobody:/tmp:/sbin/nologin
	EOF

}
function build() 
{
#	[ -d "$1" ] && (echo -n "Folder already exists - continue? [y/n] ";read _p;[[ "$_p" == [Yy] ]] ||kill -9 $$)

	echo -n "Gathering files: "
	FILES=$(for x in $PACKAGES; do
                rpm -ql $x|grep -vE "(/usr/share/doc|/usr/share/man)"
        done)
	FILES="$FILES $EXTRAS"
	EXECS=$((for x in $FILES; do
	                [ -x $x ] && (file $x|grep -vE "(script|directory|symbolic)"|cut -d':' -f1)
	        done)|sort|uniq;echo)

	OBJECTS=$((for x in $EXECS; do
	                ldd $x|awk '{$2="/";print $1;print $3}'|grep /|grep -v ':'
	                #(ldd $x|awk '{$4=""; print $3}'|grep -v \(;ldd $x|grep ld-linux|awk '{$2=""; print $1}')
	        done)|sort|uniq|grep -v dynamic|tr '\n' ' ';echo)

	LINKED_FILES=$((for x in $OBJECTS; do
	                        [ -h $x ] && readlink -f $x
	                done)|sort|uniq)

	FILES=`echo $FILES $OBJECTS $LINKED_FILES|sort|uniq`
	echo "Done."

	tar cfvp chroot.tar $FILES --hard-dereference >/dev/null 2>&1
	echo "Total files : `echo $FILES|sed -e's/\ /\n/g'|wc -l` (`du -h chroot.tar`)"
	echo -n "Unpacking and cleanup: "
	tar xvf chroot.tar --directory=$1  >/dev/null 2>&1
	rm chroot.tar
	echo "Done."
}
if [ $# = 2 ]; then
	case "$1" in
		--mysql)
			PACKAGES="mysql mysql-libs mysql-server vim-minimal glibc mailcap-2.1.31-2"
			build $2
			prep $2
			enter $2
		;;
		:--nginx)
			PACKAGES="nginx nss openssl t1lib vim-minimal glibc perl mailcap-2.1.31-2"
			build $2
			prep $2
			enter $2
		;;
		--php-fpm)
			PACKAGES="php php-cli php-common php-devel php-fpm php-gd php-imap php-ldap \
				  php-mbstring php-mysql php-pdo php-pear php-xml compat-mysql51 curl \
				  libcurl nss openssl t1lib vim-minimal glibc mailcap-2.1.31-2"
			build $2
			prep $2
			enter $2
		;;
		--httpd)
			PACKAGES="httpd httpd-devel nss php php-pear php-xml php-mysql php-cli php-imap \
				  php-gd php-pdo php-devel php-mbstring php-common php-ldap curl libcurl \
				  glibc ncurses-libs vim-minimal mailcap-2.1.31-2"
			build $2
			prep $2
			enter $2
		;;
		--enter)
			enter $2
		;;
		*)
			print_usage $0
	esac
	exit $?
else
	print_usage
fi
