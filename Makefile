# $Id: Makefile,v 1.3 2002-08-29 08:51:04 turbo Exp $

install all:	clean
	@( \
	  cp -v backup /sbin/backup-`hostname`; \
	  cp -v backup_afs.sh /afs/bayour.com/common/noarch/sbin/; \
	  cp -v update_afs.sh /afs/bayour.com/common/noarch/sbin/; \
	)

clean:
	@rm -f *~ .#*
