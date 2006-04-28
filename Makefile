# $Id: Makefile,v 1.44 2006-04-28 11:24:24 turbo Exp $

sBIN		= /afs/bayour.com/common/noarch/sbin
uBIN		= /afs/bayour.com/common/noarch/bin
sBINARIES	= backup_afs.sh update_afs.sh salvage_afs.sh qmail-runq qmail-stats.pl convert_openldap_db.pl change_openldap_db_layout.pl ldapadduser.sh qmail-qclean.sh qmail-smtpd-summary.pl qmail-summary.pl modify_ldap_database.pl scsi_list.pl scsi_reset.sh bacula-listfiles.sh bacula-listjobs.sh bacula-messages.sh bacula-status.sh check.sh

uBINARIES	= df_afs.pl list_afs_vols.sh idn.sh build-latest-spamassassin.sh cvs-rsh create_htmls.pl create_thumbs.pl renumber.pl

install all:	clean
	@(for file in $(sBINARIES) ; do \
	    cp -v $$file $(sBIN)/; \
	    for host in aurora fritz 51pegasi; do \
	      echo -n "\`$$file' -> \`$$host:/usr/local/sbin/'"; \
	      rcp -x $$file root@$$host:/usr/local/sbin/; \
	      echo; \
	    done; \
	  done; \
	  for file in $(uBINARIES) ; do \
	    cp -v $$file $(uBIN)/; \
	    for host in aurora fritz 51pegasi; do \
	      echo -n "\`$$file' -> \`$$host:/usr/local/bin/'"; \
	      rcp -x $$file root@$$host:/usr/local/bin/; \
	      echo; \
	    done; \
	  done; \
	  for host in aurora fritz 51pegasi; do \
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
	    for test in psql slapd smtp tcp; do \
	      echo -n "\`test-$$test.pl' -> \`$$host:/usr/local/sbin/test-$$test.pl'"; \
	      rcp -x test-$$test.pl root@$$host:/usr/local/sbin/; \
	      echo; \
	    done; \
	  done; \
	  echo -n "\`kprop.sh' -> \`aurora:/usr/sbin/'"; \
	  rcp -x kprop.sh root@aurora:/usr/sbin; \
	  rcp -x backup root@aurora:/sbin/backup-`hostname`; \
	  rcp -x bind9-snmp-stats.pl root@aurora:/etc/snmp/; \
	  rcp -x snmp.conf.stub snmpd.conf.stub root@aurora:/etc/snmp/; \
	  rcp -x BAYOUR-COM-MIB.txt root@aurora:/usr/share/snmp/mibs/; \
	  rcp -x check_slapd-bind9.sh root@aurora:/usr/local/sbin/; \
	  cp update_{incoming,packages}.sh /home/ftp/bin/; \
	  echo)

clean:
	@rm -f *~ .#*

$(sBINARIES): dummy
	@cp -v $@ $(sBIN)

$(uBINARIES): dummy
	@cp -v $@ $(uBIN)

dummy:
