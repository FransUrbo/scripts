# $Id: Makefile,v 1.1 2002-06-25 09:21:10 turbo Exp $

install all:	clean
	@( \
	  cp -v backup /etc/cron.daily/; \
	)

clean:
	@rm -f *~ .#*
