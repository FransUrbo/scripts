# $Id: Makefile,v 1.4 2002-09-15 14:19:47 turbo Exp $

install all:	clean
	@( \
	  cp -v backup /sbin/backup-`hostname`; \
	  cp -v backup_afs.sh /afs/bayour.com/common/noarch/sbin/; \
	  cp -v update_afs.sh /afs/bayour.com/common/noarch/sbin/; \
	)
	@for host in rmgztk morwen; do \
	  echo -n "backup-rmgztk_morwen -> $$host:/sbin/backup-$$host... "; \
	  rcp -x backup-rmgztk_morwen root@$$host:/sbin/backup-$$host; \
	  echo "done."; \
	done

clean:
	@rm -f *~ .#*
