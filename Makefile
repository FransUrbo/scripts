# $Id: Makefile,v 1.31 2004-09-18 09:00:32 turbo Exp $

sBIN		= /afs/bayour.com/common/noarch/sbin
uBIN		= /afs/bayour.com/common/noarch/bin
sBINARIES	= backup_afs.sh update_afs.sh salvage_afs.sh qmail-runq qmail-stats.pl convert_openldap_db.pl change_openldap_db_layout.pl create_cert.sh ldapadduser.sh qmail-qclean.sh qmail-smtpd-summary.pl qmail-summary.pl modify_ldap_database.pl
uBINARIES	= df_afs.pl list_afs_vols.sh idn.sh build-latest-spamassassin.sh cvs-rsh

install all:	clean
	@(for file in $(sBINARIES) ; do \
	    cp -v $$file $(sBIN)/; \
	    for host in aurora morwen ; do \
	      echo -n "\`$$file' -> \`$$host:/usr/local/sbin/'"; \
	      rcp -x $$file root@$$host:/usr/local/sbin/; \
	      echo; \
	    done; \
	  done; \
	  for file in $(uBINARIES) ; do \
	    cp -v $$file $(uBIN)/; \
	    for host in aurora morwen ; do \
	      echo -n "\`$$file' -> \`$$host:/usr/local/bin/'"; \
	      rcp -x $$file root@$$host:/usr/local/bin/; \
	      echo; \
	    done; \
	  done; \
	  for host in aurora morwen ; do \
	    echo -n "\`backup-rmgztk_morwen' -> \`$$host:/sbin/backup-$$host'"; \
	    sed -e "s@%DIRS%@`cat .dirs-$$host`@" backup-rmgztk_morwen \
	        -e "s@%HOST%@$$host@" > .TMPFILE; \
	    rcp -x .TMPFILE root@$$host:/sbin/backup-$$host; \
	    rm .TMPFILE; \
	    echo; \
	    echo -n "\`test-slapd.pl' -> \`$$host:/sbin/test-slapd.pl'"; \
	    sed -e "s@%HOST%@$$host@" < test-slapd.pl > .TMPFILE; \
	    rcp -x .TMPFILE root@$$host:/sbin/test-slapd.pl; \
	    rm .TMPFILE; \
	    echo; \
	    echo -n "\`test-smtp.pl' -> \`$$host:/usr/sbin/test-smtp.pl'"; \
	    rcp -x test-smtp.pl root@$$host:/usr/sbin/; \
	    echo; \
	  done; \
	  echo -n "\`kprop.sh' -> \`aurora:/usr/sbin/'"; \
	  rcp -x kprop.sh root@aurora:/usr/sbin; \
	  rcp -x backup root@aurora:/sbin/backup-`hostname`; \
	  cp cron.weekly /etc/cron.weekly/backup; \
	  echo)

clean:
	@rm -f *~ .#*

$(sBINARIES): dummy
	@cp -v $@ $(sBIN)

$(uBINARIES): dummy
	@cp -v $@ $(uBIN)

dummy:
