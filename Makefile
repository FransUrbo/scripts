# $Id: Makefile,v 1.15 2003-10-11 08:31:38 turbo Exp $

sBINARIES="backup_afs.sh update_afs.sh salvage_afs.sh qmail-runq qmail-stats.pl"
uBINARIES="df_afs.pl"

install all:	clean
	@(cp -v backup /sbin/backup-`hostname`; \
	  for file in $(sBINARIES) ; do \
	    cp -v $$file /afs/bayour.com/common/noarch/sbin/; \
	  done; \
	  for file in $(uBINARIES) ; do \
	    cp -v $$file /afs/bayour.com/common/noarch/bin/; \
	  done; \
	  for host in rmgztk morwen ; do \
	    echo -n "\`backup-rmgztk_morwen' -> \`$$host:/sbin/backup-$$host'"; \
	    sed -e "s@%DIRS%@`cat .dirs-$$host`@" backup-rmgztk_morwen \
	        -e "s@%HOST%@$$host@" > .TMPFILE; \
	    rcp -x .TMPFILE root@$$host:/sbin/backup-$$host; \
	    rm .TMPFILE; \
	    echo; \
	    echo -n "\`test-smtp.pl' -> \`$$host:/usr/sbin/test-smtp.pl'"; \
	    rcp -x test-smtp.pl root@$$host:/usr/sbin/; \
	    echo; \
	  done; \
	  echo -n "\`kprop.sh' -> \`rmgztk:/usr/sbin/'"; \
	  rcp -x kprop.sh root@rmgztk:/usr/sbin; \
	  cp cron.weekly /etc/cron.weekly/backup; \
	  echo)

clean:
	@rm -f *~ .#*
