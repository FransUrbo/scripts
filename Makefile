# $Id: Makefile,v 1.5 2002-11-10 10:45:34 turbo Exp $

TMPFILE = $(shell tempfile -p bkp.)

install all:	clean
	@( \
	  cp -v backup /sbin/backup-`hostname`; \
	  cp -v backup_afs.sh /afs/bayour.com/common/noarch/sbin/; \
	  cp -v update_afs.sh /afs/bayour.com/common/noarch/sbin/; \
	)
	@for host in rmgztk morwen ; do \
	  echo -n "backup-rmgztk_morwen -> $$host:/sbin/backup-$$host... "; \
	  sed -e "s@%DIRS%@`cat .dirs-$$host`@" backup-rmgztk_morwen > $TMPFILE; \
	  rcp -x $TMPFILE root@$$host:/sbin/backup-$$host; \
	  echo "done."; \
	done

clean:
	@rm -f *~ .#*
