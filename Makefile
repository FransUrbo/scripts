# $Id: Makefile,v 1.11 2003-01-31 06:45:21 turbo Exp $

install all:	clean
	@( \
	  cp -v backup /sbin/backup-`hostname`; \
	  cp -v backup_afs.sh /afs/bayour.com/common/noarch/sbin/; \
	  cp -v update_afs.sh /afs/bayour.com/common/noarch/sbin/; \
	  cp -v salvage_afs.sh /afs/bayour.com/common/noarch/sbin/; \
	  cp -v df_afs.sh /afs/bayour.com/common/noarch/sbin/; \
	)
	@for host in rmgztk morwen ; do \
	  echo -n "\`backup-rmgztk_morwen' -> \`$$host:/sbin/backup-$$host'"; \
	  sed -e "s@%DIRS%@`cat .dirs-$$host`@" backup-rmgztk_morwen \
	      -e "s@%HOST%@$$host@" > .TMPFILE; \
	  rcp -x .TMPFILE root@$$host:/sbin/backup-$$host; \
	  rm .TMPFILE; \
	  echo; \
	  echo -n "\`test-smtp.pl' -> \`$$host:/usr/sbin/test-smtp.pl'"; \
	  rcp -x test-smtp.pl root@$$host:/usr/sbin/; \
	  echo; \
	done
	@echo -n "\`kprop.sh' -> \`rmgztk:/usr/sbin/'"
	@rcp -x kprop.sh root@rmgztk:/usr/sbin
	@echo

clean:
	@rm -f *~ .#*
