#!/usr/bin/perl

# Based on 'parse_bind9stat.pl' by
# Dobrica Pavlinusic, <dpavlin@rot13.org> 
# http://www.rot13.org/~dpavlin/sysadm.html 

use strict; 
$ENV{PATH}   = "/bin:/usr/bin:/usr/sbin";

my $OID_BASE = ".1.3.6.1.4.1.8767.2.1";

my $log      = "/var/lib/named/var/log/dns-stats.log";
my $rndc     = "/usr/sbin/rndc"; 
my $delta    = "/var/tmp/"; 

my $debug    = 0;
my $arg      = '';
my $oid      = '';

my %DATA;
my $counter;
my $type;

my @counters;
my %counters = ("1" => 'success',
		"2" => 'referral',
		"3" => 'nxrrset',
		"4" => 'nxdomain',
		"5" => 'recursion',
		"6" => 'failure');

my %types    = ("1" => 'total',
		"2" => 'forward',
		"3" => 'reverse');
my @types    = qw(1 2 3);

# ----------

if(!$ENV{"PS1"} && open(DBG, ">> /tmp/bind9-stats.dbg")) {
    foreach (@ARGV) {
	print DBG $_."\n";
    }
    print DBG "------\n";
    close(DBG);
}

my $i=0;

my $count_counters;
foreach (keys %counters) {
    $count_counters++;
}

my $count_types;
foreach (keys %types) {
    $count_types++;
}

for($i=0; $ARGV[$i]; $i++) {
    if($ARGV[$i] eq '--help' || $ARGV[$i] eq '-h' || $ARGV[$i] eq '?' ) {
	&help();
    } elsif($ARGV[$i] eq '--debug' || $ARGV[$i] eq '-d') {
	$debug = 1;
    } elsif($ARGV[$i] eq '--all' || $ARGV[$i] eq '-a') {
	@counters = qw(1 2 3 4 5 6);
	undef @ARGV; # Quit here, don't go further
    } else {
	my $arg = $ARGV[$i];
	# $arg == -n => Get next OID		($oid = $ARGV[$i+1])
	# $arg == -g => Get specified OID	($oid = $ARGV[$i+1])

	$i++;

	$oid = $ARGV[$i];
	my $tmp = $oid;	$tmp =~ s/$OID_BASE//;	$tmp =~ s/^\.//;
	my ($x, $y, $z) = split('\.', $tmp);
	print "x=$x, y=$y, z=$z\n" if($debug);

	if(!$x) {
	    # $OID_BASE => $OID_BASE.1
	    print "This is the top\n" if($debug);

	    if($arg eq '-n') {
		@counters = qw(1);
	    } else {
		print "No value in this object - exiting!\n" if($debug);
		exit 1;
	    }
	} elsif($z) {
	    # $OID_BASE.x.y.z => To many sublevels - exit
	    print "To many sublevels - exit\n" if($debug);
	    exit 1;
	} elsif(($x && ($x < 1) || ($x > $count_counters)) ||
		($y && ($y < 1) || ($y > $count_types)))
	{
	    # Non-existant branch
	    print "Non-existant branch\n" if($debug);
	    exit 1;
	} elsif(!$y) {
	    # $OID_BASE.x => $OID_BASE.x.1

	    if($arg eq '-n') {
		@counters = $x;
		@types    = qw(1);
	    } else {
		print "No value in this object - exiting!\n" if($debug);
		exit 1;
	    }
	} elsif(($arg eq '-n') && ($x == $count_counters) && ($y == $count_types)) {
	    # We've reach the end of the line, there IS no next OID!
	    exit 1;
	} else {
	    if($arg eq '-n') {
		# $OID_BASE.x.y => $OID_BASE.x.y+1  (if y != max y)
		# $OID_BASE.x.y => $OID_BASE.x+1.1  (if y == max y)
		if(($y == $count_types) && ($x != $count_counters)) {
		    $x++;
		    $y = 1;
		} else {
		    $y++;
		}

	    } # else fall through...

	    @counters = $x;
	    @types    = $y;
	}
    }
}


print "OID: $OID_BASE",".",$counters[0],".",$types[0],"\n" if($debug);

# ----------

system "$rndc stats"; 

my %total; 
my %forward; 
my %reverse; 

my $tmp=$log; 
$tmp=~s/\W/_/g; 
$delta.=$tmp.".offset"; 

open(DUMP,$log) || die "$log: $!"; 

if (-e $delta) { 
    open(D,$delta) || die "can't open delta file '$delta' for '$log': $!"; 
    my $offset=<D>; 
    chomp $offset; 
    close(D); 
    my $log_size = -s $log; 
    if ($offset <= $log_size) { 
	seek(DUMP,$offset,0); 
    } 
} 

while(<DUMP>) { 
    next if /^(---|\+\+\+)/; 
    chomp; 
    my ($what,$nr,$direction) = split(/\s+/,$_,3); 
    if (! $direction) { 
	$DATA{"total"}{$what} += $nr; 
    } elsif ($direction =~ m/in-addr.arpa/) { 
	$DATA{"reverse"}{$what} += $nr; 
    } else { 
	$DATA{"forward"}{$what} += $nr; 
    } 

} 

open(D,"> $delta") || die "can't open delta file '$delta' for log '$log': $!"; 
print D tell(DUMP); 
close(D); 

close(DUMP); 

# ----------

my $i;
my $nr_count;
my $nr_type;

foreach (@counters) { 
    $nr_count = $_;
    $counter  = $counters{$nr_count};

    printf("%-10s\n", $counter) if($debug);
    foreach (@types) {
	$nr_type = $_;

	if(!$debug) {
	    my @tmp = split('\.', $OID_BASE.".".$nr_count.".".$nr_type);

	    print '.';
	    for($i=1; $tmp[$i]; $i++) {
		print $tmp[$i];

		if($tmp[$i+1]) {
		    print ".";
		} else {
		    $tmp[$i]++;
		}

	    }
	    print "\n";
	}

	$type = $types{$nr_type};

	printf(" %-7s ", $type) if($debug);
	print "gauge\n"    if(!$debug);
	print $DATA{$type}{$counter},"\n";
    }
    printf("\n") if($debug);
} 

