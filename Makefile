# $Id: Makefile,v 1.2 2002-08-28 14:03:50 turbo Exp $

install all:	clean
	@( \
	  cp -v backup /etc/cron.daily/; \
	  cp -v backup_afs.sh /afs/bayour.com/common/noarch/sbin/; \
	  cp -v update_afs.sh /afs/bayour.com/common/noarch/sbin/; \
	)

clean:
	@rm -f *~ .#*
