#!/usr/bin/perl -w

# $Id: modify_ldap_database.pl,v 1.2 2004-09-16 05:21:05 turbo Exp $

# This script will convert a OpenLDAP v2.0 database
# to a OpenLDAP 2.[12] one.
# In addition to this, the script will add ACI's
# and change the TopDN from 'dc=net' to 'c=SE'.
#
# Resent addition will also create a special proxy
# user object (and add this object to ACI's with
# SEARCH rights to the authentication attributes)
# to be used on the LDAP proxy's (which uses
# back-ldap).

use MIME::Base64;

# The administration users.
@ADMINS	= ("uid=turbo,ou=People,o=Swe.Net AB,c=SE",
	   "uid=malin,ou=People,o=Swe.Net AB,c=SE",
	   "uid=ma,ou=People,o=Swe.Net AB,c=SE");

# The special QmailLDAP/Controls user.
@QMAIL	= ("uid=qmail,ou=People,o=Swe.Net AB,c=SE");

# The special proxy user.
@PROXY	= ("uid=proxy,ou=System,o=Swe.Net AB,c=SE");

# --------------------------------------------------

# Load the whole LDIF
$count = 0;
while(! eof(STDIN)) {
    $line = <STDIN>; chomp($line);
    push(@FILE, $line);
    $count++;
}

# Go through the LDIF, modify it according to the new
# OpenLDAP v2.2.x standards (with ACI's etc).
for($i=0; $i < $count; $i++) {
    if($FILE[$i]) {
	# Only care/modify SOME attributes
	if(($FILE[$i] !~ /^entryCSN/i)		&&
	   ($FILE[$i] !~ /^entryUUID/i)		&&
	   ($FILE[$i] !~ /no data for entry/)	&&
	   ($FILE[$i] !~ /^creatorsName/i)	&&
	   ($FILE[$i] !~ /^modifiersName/i)	&&
	   ($FILE[$i] !~ /^createTimestamp/i)	&&
	   ($FILE[$i] !~ /^modifyTimestamp/i)) {

	    # Catch multi lines (regenerate a NEW line).
	    # --------------------------------------
	    if($FILE[$i+1] =~ /^ /) {
		$line = $FILE[$i];

		while($FILE[$i+1] =~ /^ /) {
		    $next  = $FILE[$i+1];
		    $next =~ s/^\ //;
		    $line .= $next;
		    $i++;
		}
	    } else {
		$line = $FILE[$i];
	    }
	    
	    # Change BaseDN from 'dc=net' to 'c=SE'.
	    # --------------------------------------
	    if($line =~ /^dn:: /) {
		# BASE64 decode string
		$string = $line; $string =~ s/dn:: //i;
		$string = decode_base64("$string");
		
		# Change suffix
		$string =~ s/dc=net$/c=SE/i;

		# Remember the DN
		$DN     = $string;

		# BASE64 encode string
		$string = encode_base64("$string");
		chomp($string); # encode_base64() ADDS a newline!
		if($string =~ /.*\n/) {
		    $string =~ s/\n//;
		}
		
		$line = "dn:: $string";
	    } elsif(($line =~ /^dn: /) && ($line !~ /^dn: cn=qmail/i)) {
		# Change suffix (but NOT on the QmailLDAP user)
		$line =~ s/dc=net$/c=SE/i;

		# Remember the DN
		$string = $line; $string =~ s/dn: //i;
		$DN     = $string;

	    # Since the BaseDN was changed, also change inside the object
	    # --------------------------------------
	    } elsif(($DN eq 'c=SE') && ($line =~ /^dc: net/)) {
		$line =~ s/dc: net/c: SE/i;
	    } elsif(($DN eq 'c=SE') && ($line =~ /^objectClass: domain/i)) {
		$line =~ s/objectClass: domain/objectClass: country/i;

	    # Change '{KERBEROS}' to '{SASL}' (same value othervise)
	    # --------------------------------------
	    } elsif($line =~ /^userPassword:: /i) {
		# BASE64 decode string
		$string = $line; $string =~ s/userPassword:: //i;
		$string = decode_base64("$string");

		if($string =~ /KERBEROS/i) {
		    $string =~ s/{KERBEROS}//i;
		    $string = "{SASL}$string";
		}

		$line = "userPassword: $string";

	    # Some user object classes can't be used for one reason or the other.
	    # --------------------------------------
	    } elsif(($DN =~ /^uid=/) && 
		    (($line =~ /^objectClass: organizationalPerson/i) ||
		     ($line =~ /^objectClass: pilotPerson/i) ||
		     ($line =~ /^givenName: /i)))
	    {
		next;

	    # The attribute 'mailQuota' have been split into two
	    # (mailQuotaSize and mailQuotaCount)
	    # --------------------------------------
	    } elsif(($DN =~ /^uid=/) && ($line =~ /^mailQuota: /i)) {
		$quota =  $line;
		$quota =~ s/.*: //;
		if($quota =~ /\ /) {
		    ($size, $count) = split($quota);
		    if($size) {
			print "mailQuotaSize: $size\n";
		    } elsif($count) {
			print "mailQuotaCount: $count\n";
		    }
		} else {
		    # The quota value is bogus, just leave it out
		    next;
		}

	    # The attribute 'personalTitle' is just known as 'title' now.
	    # --------------------------------------
	    } elsif(($DN =~ /^uid=/) && ($line =~ /^personalTitle/i)) {
		$line =~ s/personalTitle/title/i;

	    # The 'simpleSecurityObject' is no more. Must use 'account' (with s/cn/uid/g)
	    # as well.
	    # --------------------------------------
	    } elsif(($DN =~ /^uid=qmail/) && ($line =~ /^cn: qmail/i)) {
		$line =~ s/cn: qmail/uid: qmail/i;
	    } elsif(($DN =~ /^uid=qmail/) && ($line =~ /^objectClass: simpleSecurityObject/i)) {
		print "$line\n";
		$line = "objectClass: account";

	    # Since 'simpleSecurityObject' was replaced with 'account', the DN to
	    # the qmail-ldap user must change from 'cn' to 'uid'.
	    # --------------------------------------
	    } elsif($line =~ /^dn: cn=qmail/i) {
		# Change suffix (but NOT on the QmailLDAP user)
		$line =~ s/dc=net$/c=SE/i;

		# Change reference attribute
		$line =~ s/cn=qmail/uid=qmail/i;

		# Remember the (new) DN
		$string = $line; $string =~ s/dn: //i;
		$DN     = $string;

	    # The phpQLAdmin object 'phpQLAdminBranch' have been split in two
	    # --------------------------------------
	    } elsif(($DN =~ /^o=/) &&
		    (($line =~ /useControls/i)		|| ($line =~ /useEzmlm/i)		||
		     ($line =~ /useBind9/i)		|| ($line =~ /useWebSrv/i)		||
		     ($line =~ /autoReload/i)		|| ($line =~ /allowServerChange/i)	||
		     ($line =~ /whoAreWe/i)		|| ($line =~ /language/i)		||
		     ($line =~ /hostMaster/i)		|| ($line =~ /ezmlmBinaryPath/i)	||
		     ($line =~ /krb5RealmName/i)	|| ($line =~ /krb5AdminServer/i)	||
		     ($line =~ /krb5PrincipalName/i)	|| ($line =~ /krb5AdminKeytab/i)	||
		     ($line =~ /krb5AdminCommandPath/i)	|| ($line =~ /controlBaseDn/i)		||
		     ($line =~ /ezmlmAdministrator/i)	|| ($line =~ /controlsAdministrator/i)))
	    {
		print "$line\n";
		$line = "objectClass: phpQLAdminGlobal";
		push(@OC, "phpQLAdminGlobal");

	    # Remember the object class
	    # --------------------------------------
	    } elsif($line =~ /^objectClass: /i) {
		$oc = (split(' ', $line))[1];
		push(@OC, $oc);
	    }

	    print "$line\n";
	}
    } elsif($FILE[$i+1]) {
	$ACI = 0;

	# We have an array with object classes. Convert that to an flat variable
	# (for simplicity)
	undef($OC);
	foreach $oc (@OC) {
	    $OC .= "$oc ";
	}

	# Before we add the next object, add the ACI's (objectClass: OpenLDAPacl).
	print "OpenLDAPaci: ".$ACI++."#entry#grant;r,s,c;objectClass,[entry]#public#\n";
	
	if($DN !~ /\,/) {
	    # Top DN - make sure some phpQLAdmin attribs are readable
	    $phpQLAdminAttribs = ",userReference,branchReference,administrator";
	} else {
	    $phpQLAdminAttribs = '';
	}
	
	# ?
	# --------------------------------------
	if($DN =~ /^dc/) {
	    print "OpenLDAPaci: ".$ACI++."#entry#grant;r,s,c;dc$phpQLAdminAttribs#public#\n";

	# The BaseDN
	# --------------------------------------
	} elsif(($DN =~ /^c/) && ($DN !~ /^cn/)) {
	    print "OpenLDAPaci: ".$ACI++."#entry#grant;r,s,c;c$phpQLAdminAttribs#public#\n";

	# This is a group object
	# --------------------------------------
	} elsif(($DN =~ /^cn/) && ($OC =~ /posixGroup/i)) {
	    print "OpenLDAPaci: ".$ACI++."#entry#grant;r,s,c;cn,gidNumber$phpQLAdminAttribs#public#\n";

	# This is a QmailLDAP/Controls object - Allow the Qmail user(s) read access to what it
	# needs to have access to...
	# --------------------------------------
	} elsif(($DN =~ /^cn/) && ($OC =~ /qmailControl/i)) {
	    foreach $qmail (@QMAIL) {
		print "OpenLDAPaci: ".$ACI++."#entry#grant;r,s,c;[all]#access-id#$qmail\n";
	    }

        # This is a user object
	# --------------------------------------
	} elsif($DN =~ /^uid/) {
	    # To be able to do simple bind, the user need 'auth' privileges (not read!)
	    # for the 'userPassword' attribute.
	    print "OpenLDAPaci: ".$ACI++."#entry#grant;x;userPassword$phpQLAdminAttribs#public#\n";

	    # To be able to do SASL/GSSAPI, the user needs 'auth' privileges (not read!)
	    # for the 'krb5PrincipalName' attribute.
	    print "OpenLDAPaci: ".$ACI++."#entry#grant;x;krb5PrincipalName$phpQLAdminAttribs#public#\n";

	    # To be able to do SASL/EXTERNAL, we need 'auth' privileges (not read!)
	    # for the 'mail' and 'mailAlternateAddress' attributes.
	    print "OpenLDAPaci: ".$ACI++."#entry#grant;x;cn,mail,mailAlternateAddress$phpQLAdminAttribs#public#\n";

	    # To be able to ANY authentication on a LDAP proxy (using back-{meta,ldap}), the special
	    # proxy user needs SEARCH access to the 'userPassword', 'krb5PrincipalName', 'mail' and
	    # 'mailAlternateAddress' attributes.
	    foreach $proxy (@PROXY) {
		print "OpenLDAPaci: ".$ACI++."#entry#grant;s;userPassword,krb5PrincipalName,mail,mailAlternateAddress$phpQLAdminAttribs#access-id#$proxy\n";
	    }

	    # ------------------
	    
	    # Some things must be anonymously/publicly readable to be able to allow the user to login
	    # These are readable globaly in /etc/passwd anyway...
	    print "OpenLDAPaci: ".$ACI++."#entry#grant;r,s,c;uid,cn,accountStatus,uidNumber,gidNumber,gecos,";
	    print "homeDirectory,loginShell$phpQLAdminAttribs#public#\n";
	    
	    # Allow the Qmail user(s) read access to what it needs to have access to...
	    foreach $qmail (@QMAIL) {
		print "OpenLDAPaci: ".$ACI++."#entry#grant;r,s,c;mail,mailAlternateAddress,mailHost,";
		print "mailQuotaSize,mailQuotaCount,accountStatus,deliveryMode,userPassword,mailMessageStore,";
		print "deliveryProgramPath#access-id#$qmail\n";
	    }

	    # Some values should be readable by authenticated users
	    print "OpenLDAPaci: ".$ACI++."#entry#grant;r,s,c;sn,givenName,homePostalAddress,mobile,homePhone,";
	    print "labeledURI,mailForwardingAddress,street,physicalDeliveryOfficeName,mailMessageStore,o,l,";
	    print "st,telephoneNumber,postalCode,title#users#\n";
	    
	    # Some values should be writable by 'self' (owner of the object)
	    print "OpenLDAPaci: ".$ACI++."#entry#grant;w,r,s,c;sn,givenName,homePostalAddress,mobile,homePhone,";
	    print "labeledURI,mailForwardingAddress,street,physicalDeliveryOfficeName,o,l,st,telephoneNumber,";
	    print "postalCode,title,deliveryMode,userPassword#self#\n";

	# This is an organization object
	# --------------------------------------
	} elsif($DN =~ /^o/) {
	    print "OpenLDAPaci: ".$ACI++."#entry#grant;r,s,c;o$phpQLAdminAttribs#public#\n";

	# This is an organization unit object
	# --------------------------------------
	} elsif($DN =~ /^ou/) {
	    print "OpenLDAPaci: ".$ACI++."#entry#grant;r,s,c;ou$phpQLAdminAttribs#public#\n";

	# This is a DNS object
	# --------------------------------------
	} elsif($DN =~ /^relativeDomainName/) {
	    print "OpenLDAPaci: ".$ACI++."#entry#grant;r,s,c;relativeDomainName,zoneName,DNSTTL,DNSClass,";
	    print "ARecord,MDRecord,MXRecord,NSRecord,SOARecord,CNAMERecord,PTRRecord,HINFORecord,";
	    print "MINFORecord,TXTRecord,SIGRecord,KEYRecord,AAAARecord,LOCRecord,NXTRecord,SRVRecord,";
	    print "NAPTRRecord,KXRecord,CERTRecord,A6Record,DNAMERecord$phpQLAdminAttribs#public#\n";
	}
	
	# Add the 'super admins'
	# --------------------------------------
	foreach $subj (@ADMINS) {
	    print "OpenLDAPaci: ".$ACI++."#entry#grant;w,r,s,c,x;[all]#access-id#$subj\n";
	}
	
	# Prepare for next object (one empty line between each object)
	print "\n";

	# Forget the object class(es), we're starting with a new object...
	undef(@OC);
    } else {
	# This is the end of the file... Nothing yet (?)
    }
}

# Now when the whole DB have been converted - some additions
print <<EOF

dn: cn=ida.swe.net,ou=QmailLDAP,o=Swe.Net AB,c=SE
objectClass: top
objectClass: qmailControl
cn: ida.swe.net
ldapUid: 3001
ldapServer: alfred.swe.net
ldapRebind: 1
ldapBaseDN: c=SE
quotaWarning: User is above quota level!
ldapDefaultDotMode: ldapwithprog
plusDomain: test.swe.net
ldapDefaultQuota: 102400000000S,1000000C
ldapGid: 3001
ldapCluster: 1
concurrencyLocal: 20
concurrencyRemote: 20
pbsServers: 127.0.0.1
pbsPort: 2821
pbsIp: 127.0.0.1
dirMaker: /usr/lib/qmail/create_dirs.pl
defaultDomain: swe.net
locals: ackberger.se
locals: acmab.se
locals: agenturkompaniet.com
locals: ahjackson.se
locals: american-lincoln.se
locals: americancleaningmachines.se
locals: axelericsson.se
locals: bamsebo.org
locals: bergerlind.com
locals: bergerlind.se
locals: bergfeldt.se
locals: bilfargsbutiken.com
locals: bilfargsbutiken.se
locals: biotech.swe.net
locals: capline.se
locals: changeit.se
locals: cidelotts.se
locals: cs.swe.net
locals: cyberott.com
locals: databitentech.com
locals: datapedagogen.com
locals: eliteperformance.swe.net
locals: ida.ackberger.se
locals: ida.acmab.se
locals: ida.agenturkompaniet.com
locals: ida.ahjackson.se
locals: ida.axelericsson.se
locals: ida.bamsebo.org
locals: ida.bergerlind.se
locals: ida.bergfeldt.se
locals: ida.bilfargsbutiken.se
locals: ida.biotech.swe.net
locals: ida.capline.se
locals: ida.changeit.se
locals: ida.cs.swe.net
locals: ida.cyberott.com
locals: ida.databitentech.com
locals: ida.datapedagogen.com
locals: ida.eliteperformance.swe.net
locals: ida.essentys.com
locals: ida.explosivaumea.com
locals: ida.fashioncolor.se
locals: ida.fbiab.se
locals: ida.finnheat.se
locals: ida.frennesia.se
locals: ida.fritidsservice.se
locals: ida.fromell.se
locals: ida.gerletravel.se
locals: ida.gostajacobsson.swe.net
locals: ida.granelli.nu
locals: ida.grizzly.swe.net
locals: ida.heljestrand.se
locals: ida.hund.net
locals: ida.informator.net
locals: ida.inlar.se
locals: ida.isoab.se
locals: ida.jarnbrott.com
locals: ida.kasystem.se
locals: ida.landsfiskalen.se
locals: ida.lassesfarg.se
locals: ida.lundbyel.se
locals: ida.luwasa.se
locals: ida.mac.hydroscand.se
locals: ida.maccon.se
locals: ida.mesterhazy.com
locals: ida.morrgarden.com
locals: ida.naken.nu
locals: ida.nivex.se
locals: ida.nordec.se
locals: ida.odisea.se
locals: ida.ometall.se
locals: ida.partsmart.se
locals: ida.pellestrom.se
locals: ida.perfectclean.se
locals: ida.petersotare.se
locals: ida.piaggio.se
locals: ida.pib.nu
locals: ida.polarisworld.se
locals: ida.raydar.se
locals: ida.rwi.se
locals: ida.samsakgruppen.se
locals: ida.sanplat.com
locals: ida.seabel.se
locals: ida.shetlandspony.com
locals: ida.smarsgarden.se
locals: ida.sotarenstockholm.nu
locals: ida.soundpush.com
locals: ida.spanienbostad.se
locals: ida.special-t.biz
locals: ida.sportab.se
locals: ida.stensjogarden.org
locals: ida.stroke-of-genius.com
locals: ida.surte.se
locals: ida.sverigedirekt.org
locals: ida.swe.net
locals: ida.tailors.se
locals: ida.ten-chi-jin.se
locals: ida.test.swe.net
locals: ida.tommyelf.com
locals: ida.unibase.se
locals: ida.varmlandsstadmaskiner.se
locals: ida.vastalpin.se
locals: ida.videndus.com
locals: ida.yogastudion.se
locals: essentys.com
locals: essentys.se
locals: explosivaumea.com
locals: fashioncolor.se
locals: fbiab.com
locals: fbiab.se
locals: finnheat.com
locals: finnheat.fi
locals: finnheat.se
locals: frennesia.se
locals: fritidsservice.se
locals: fromell.pp.se
locals: fromell.se
locals: gerletravel.se
locals: gostajacobsson.swe.net
locals: granelli.nu
locals: grizzly-shipping.se
locals: grizzly.swe.net
locals: heljestrand.se
locals: hund.net
locals: informator.net
locals: inlar.se
locals: isoab.se
locals: jarnbrott.com
locals: joyful.swe.net
locals: kasystem.se
locals: landsfiskalen.se
locals: lassesfarg.se
locals: localhost
locals: lundbyel.se
locals: luwasa.se
locals: mac.hydroscand.se
locals: maccon.se
locals: mesterhazy.com
locals: morrgarden.com
locals: naken.nu
locals: nivex.se
locals: noni.swe.net
locals: nordec.se
locals: odisea.se
locals: ometall.info
locals: ometall.lv
locals: ometall.se
locals: onnheim.se
locals: oor.se
locals: pargas.nu
locals: parksystem.no
locals: parksystem.se
locals: partsmart.se
locals: pellestrom.se
locals: perfectclean.se
locals: petersotare.com
locals: petersotare.se
locals: piaggio.se
locals: pib.nu
locals: polarisworld.se
locals: raydar.se
locals: rwi.se
locals: safecracker.se
locals: samsakgruppen.se
locals: sanplat.com
locals: schlein.se
locals: seabel.se
locals: seabmarine.se
locals: shetlandspony.com
locals: shetlandspony.se
locals: smarsgarden.se
locals: sommarsex.nu
locals: sotaren.swe.net
locals: sotarenstockholm.nu
locals: soundpush.com
locals: spanienbostad.com
locals: spanienbostad.se
locals: special-t.biz
locals: sportab.se
locals: stensjogarden.org
locals: stroke-of-genius.com
locals: surte.se
locals: sverigedirekt.org
locals: swe.net
locals: swenet.se
locals: tailors.se
locals: ten-chi-jin.se
locals: test.swe.net
locals: test1.swe.net
locals: test2.swe.net
locals: test3.swe.net
locals: tommyelf.com
locals: unibase.se
locals: varmlandsstadmaskiner.se
locals: vastalpin.se
locals: videndus.com
locals: vilarma.se
locals: xn--nnheim-vxa.se
locals: yogastudion.se
locals: lindh.net
rcptHosts: ackberger.se
rcptHosts: acmab.se
rcptHosts: agenturkompaniet.com
rcptHosts: ahjackson.se
rcptHosts: american-lincoln.se
rcptHosts: americancleaningmachines.se
rcptHosts: axelericsson.se
rcptHosts: bamsebo.org
rcptHosts: bergerlind.com
rcptHosts: bergerlind.se
rcptHosts: bergfeldt.se
rcptHosts: bilfargsbutiken.com
rcptHosts: bilfargsbutiken.se
rcptHosts: biotech.swe.net
rcptHosts: capline.se
rcptHosts: changeit.se
rcptHosts: cidelotts.se
rcptHosts: cs.swe.net
rcptHosts: cyberott.com
rcptHosts: databitentech.com
rcptHosts: datapedagogen.com
rcptHosts: eliteperformance.swe.net
rcptHosts: ida.ackberger.se
rcptHosts: ida.acmab.se
rcptHosts: ida.agenturkompaniet.com
rcptHosts: ida.ahjackson.se
rcptHosts: ida.axelericsson.se
rcptHosts: ida.bamsebo.org
rcptHosts: ida.bergerlind.se
rcptHosts: ida.bergfeldt.se
rcptHosts: ida.bilfargsbutiken.se
rcptHosts: ida.biotech.swe.net
rcptHosts: ida.capline.se
rcptHosts: ida.changeit.se
rcptHosts: ida.cs.swe.net
rcptHosts: ida.cyberott.com
rcptHosts: ida.databitentech.com
rcptHosts: ida.datapedagogen.com
rcptHosts: ida.eliteperformance.swe.net
rcptHosts: ida.essentys.com
rcptHosts: ida.explosivaumea.com
rcptHosts: ida.fashioncolor.se
rcptHosts: ida.fbiab.se
rcptHosts: ida.finnheat.se
rcptHosts: ida.frennesia.se
rcptHosts: ida.fritidsservice.se
rcptHosts: ida.fromell.se
rcptHosts: ida.gerletravel.se
rcptHosts: ida.gostajacobsson.swe.net
rcptHosts: ida.granelli.nu
rcptHosts: ida.grizzly.swe.net
rcptHosts: ida.heljestrand.se
rcptHosts: ida.hund.net
rcptHosts: ida.informator.net
rcptHosts: ida.inlar.se
rcptHosts: ida.isoab.se
rcptHosts: ida.jarnbrott.com
rcptHosts: ida.kasystem.se
rcptHosts: ida.landsfiskalen.se
rcptHosts: ida.lassesfarg.se
rcptHosts: ida.lundbyel.se
rcptHosts: ida.luwasa.se
rcptHosts: ida.mac.hydroscand.se
rcptHosts: ida.maccon.se
rcptHosts: ida.mesterhazy.com
rcptHosts: ida.morrgarden.com
rcptHosts: ida.naken.nu
rcptHosts: ida.nivex.se
rcptHosts: ida.nordec.se
rcptHosts: ida.odisea.se
rcptHosts: ida.ometall.se
rcptHosts: ida.partsmart.se
rcptHosts: ida.pellestrom.se
rcptHosts: ida.perfectclean.se
rcptHosts: ida.petersotare.se
rcptHosts: ida.piaggio.se
rcptHosts: ida.pib.nu
rcptHosts: ida.polarisworld.se
rcptHosts: ida.raydar.se
rcptHosts: ida.rwi.se
rcptHosts: ida.samsakgruppen.se
rcptHosts: ida.sanplat.com
rcptHosts: ida.seabel.se
rcptHosts: ida.shetlandspony.com
rcptHosts: ida.smarsgarden.se
rcptHosts: ida.sotarenstockholm.nu
rcptHosts: ida.soundpush.com
rcptHosts: ida.spanienbostad.se
rcptHosts: ida.special-t.biz
rcptHosts: ida.sportab.se
rcptHosts: ida.stensjogarden.org
rcptHosts: ida.stroke-of-genius.com
rcptHosts: ida.surte.se
rcptHosts: ida.sverigedirekt.org
rcptHosts: ida.swe.net
rcptHosts: ida.tailors.se
rcptHosts: ida.ten-chi-jin.se
rcptHosts: ida.test.swe.net
rcptHosts: ida.tommyelf.com
rcptHosts: ida.unibase.se
rcptHosts: ida.varmlandsstadmaskiner.se
rcptHosts: ida.vastalpin.se
rcptHosts: ida.videndus.com
rcptHosts: ida.yogastudion.se
rcptHosts: essentys.com
rcptHosts: essentys.se
rcptHosts: explosivaumea.com
rcptHosts: fashioncolor.se
rcptHosts: fbiab.com
rcptHosts: fbiab.se
rcptHosts: finnheat.com
rcptHosts: finnheat.fi
rcptHosts: finnheat.se
rcptHosts: frennesia.se
rcptHosts: fritidsservice.se
rcptHosts: fromell.pp.se
rcptHosts: fromell.se
rcptHosts: gerletravel.se
rcptHosts: gostajacobsson.swe.net
rcptHosts: granelli.nu
rcptHosts: grizzly-shipping.se
rcptHosts: grizzly.swe.net
rcptHosts: heljestrand.se
rcptHosts: hund.net
rcptHosts: informator.net
rcptHosts: inlar.se
rcptHosts: isoab.se
rcptHosts: jarnbrott.com
rcptHosts: joyful.swe.net
rcptHosts: kasystem.se
rcptHosts: landsfiskalen.se
rcptHosts: lassesfarg.se
rcptHosts: localhost
rcptHosts: lundbyel.se
rcptHosts: luwasa.se
rcptHosts: mac.hydroscand.se
rcptHosts: maccon.se
rcptHosts: mesterhazy.com
rcptHosts: morrgarden.com
rcptHosts: naken.nu
rcptHosts: nivex.se
rcptHosts: noni.swe.net
rcptHosts: nordec.se
rcptHosts: odisea.se
rcptHosts: ometall.info
rcptHosts: ometall.lv
rcptHosts: ometall.se
rcptHosts: onnheim.se
rcptHosts: oor.se
rcptHosts: pargas.nu
rcptHosts: parksystem.no
rcptHosts: parksystem.se
rcptHosts: partsmart.se
rcptHosts: pellestrom.se
rcptHosts: perfectclean.se
rcptHosts: petersotare.com
rcptHosts: petersotare.se
rcptHosts: piaggio.se
rcptHosts: pib.nu
rcptHosts: polarisworld.se
rcptHosts: raydar.se
rcptHosts: rwi.se
rcptHosts: safecracker.se
rcptHosts: samsakgruppen.se
rcptHosts: sanplat.com
rcptHosts: schlein.se
rcptHosts: seabel.se
rcptHosts: seabmarine.se
rcptHosts: shetlandspony.com
rcptHosts: shetlandspony.se
rcptHosts: smarsgarden.se
rcptHosts: sommarsex.nu
rcptHosts: sotaren.swe.net
rcptHosts: sotarenstockholm.nu
rcptHosts: soundpush.com
rcptHosts: spanienbostad.com
rcptHosts: spanienbostad.se
rcptHosts: special-t.biz
rcptHosts: sportab.se
rcptHosts: stensjogarden.org
rcptHosts: stroke-of-genius.com
rcptHosts: surte.se
rcptHosts: sverigedirekt.org
rcptHosts: swe.net
rcptHosts: swenet.se
rcptHosts: tailors.se
rcptHosts: ten-chi-jin.se
rcptHosts: test.swe.net
rcptHosts: test1.swe.net
rcptHosts: test2.swe.net
rcptHosts: test3.swe.net
rcptHosts: tommyelf.com
rcptHosts: unibase.se
rcptHosts: varmlandsstadmaskiner.se
rcptHosts: vastalpin.se
rcptHosts: videndus.com
rcptHosts: vilarma.se
rcptHosts: xn--nnheim-vxa.se
rcptHosts: yogastudion.se
rcptHosts: lindh.net
OpenLDAPaci: 0#entry#grant;r,s,c;objectClass,[entry]#public#
OpenLDAPaci: 1#entry#grant;r,s,c;[all]#access-id#uid=qmail,ou=People,o=Swe.Net AB,c=SE
OpenLDAPaci: 2#entry#grant;w,r,s,c,x;[all]#access-id#uid=turbo,ou=People,o=Swe.Net AB,c=SE
OpenLDAPaci: 3#entry#grant;w,r,s,c,x;[all]#access-id#uid=malin,ou=People,o=Swe.Net AB,c=SE
OpenLDAPaci: 4#entry#grant;w,r,s,c,x;[all]#access-id#uid=ma,ou=People,o=Swe.Net AB,c=SE

dn: ou=System,o=Swe.Net AB,c=SE
ou: System
objectClass: top
objectClass: organizationalUnit
OpenLDAPaci: 0#entry#grant;r,s,c;objectClass,[entry]#public#
OpenLDAPaci: 1#entry#grant;r,s,c;o#public#
OpenLDAPaci: 2#entry#grant;w,r,s,c,x;[all]#access-id#uid=turbo,ou=People,o=Swe.Net AB,c=SE
OpenLDAPaci: 3#entry#grant;w,r,s,c,x;[all]#access-id#uid=malin,ou=People,o=Swe.Net AB,c=SE
OpenLDAPaci: 4#entry#grant;w,r,s,c,x;[all]#access-id#uid=ma,ou=People,o=Swe.Net AB,c=SE

dn: uid=proxy,ou=System,o=Swe.Net AB,c=SE
objectClass: top
objectClass: simpleSecurityObject
objectClass: account
userPassword: {MD5}72BtbcQF/HcjbK0RnEKgAA==
uid: proxy
OpenLDAPaci: 0#entry#grant;r,s,c;objectClass,[entry]#public#
OpenLDAPaci: 1#entry#grant;x;userPassword#public#
OpenLDAPaci: 2#entry#grant;x;krb5PrincipalName#public#
OpenLDAPaci: 3#entry#grant;x;cn,mail,mailAlternateAddress#public#
OpenLDAPaci: 4#entry#grant;r,s,c;uid,cn,accountStatus,uidNumber,gidNumber,gecos,homeDirectory,loginShell#public#
OpenLDAPaci: 5#entry#grant;r,s,c;mail,mailAlternateAddress,mailHost,mailQuotaSize,mailQuotaCount,accountStatus,deliveryMode,userPassword,mailMessageStore,deliveryProgramPath#access-id#uid=qmail,ou=People,o=Swe.Net AB,c=SE
OpenLDAPaci: 6#entry#grant;r,s,c;sn,givenName,homePostalAddress,mobile,homePhone,labeledURI,mailForwardingAddress,street,physicalDeliveryOfficeName,mailMessageStore,o,l,st,telephoneNumber,postalCode,title#users#
OpenLDAPaci: 7#entry#grant;w,r,s,c;sn,givenName,homePostalAddress,mobile,homePhone,labeledURI,mailForwardingAddress,street,physicalDeliveryOfficeName,o,l,st,telephoneNumber,postalCode,title,deliveryMode,userPassword#self#
OpenLDAPaci: 8#entry#grant;w,r,s,c,x;[all]#access-id#uid=turbo,ou=People,o=Swe.Net AB,c=SE
OpenLDAPaci: 9#entry#grant;w,r,s,c,x;[all]#access-id#uid=malin,ou=People,o=Swe.Net AB,c=SE
OpenLDAPaci: 10#entry#grant;w,r,s,c,x;[all]#access-id#uid=ma,ou=People,o=Swe.Net AB,c=SE
EOF
    ;
