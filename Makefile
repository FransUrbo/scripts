# $Id: Makefile,v 1.8 2002-11-21 09:53:14 turbo Exp $

install all:	clean
	@( \
	  cp -v backup /sbin/backup-`hostname`; \
	  cp -v backup_afs.sh /afs/bayour.com/common/noarch/sbin/; \
	  cp -v update_afs.sh /afs/bayour.com/common/noarch/sbin/; \
	)
	@for host in rmgztk morwen ; do \
	  echo -n "backup-rmgztk_morwen -> $$host:/sbin/backup-$$host... "; \
	  sed -e "s@%DIRS%@`cat .dirs-$$host`@" backup-rmgztk_morwen \
	      -e "s@%HOST%@$$host@" > .TMPFILE; \
	  rcp -x .TMPFILE root@$$host:/sbin/backup-$$host; \
	  rm .TMPFILE; \
	  echo "done."; \
	  echo -n "test-smtp.pl -> $$host:/usr/sbin/test-smtp.pl... "; \
	  rcp -x test-smtp.pl root@$$host:/usr/sbin/; \
	  echo "done."; \
	done
	rcp -x kprop.sh root@rmgztk:/usr/sbin

clean:
	@rm -f *~ .#*
