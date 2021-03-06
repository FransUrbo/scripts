#!/usr/bin/perl -w

# You need to have ZoL checked out in /usr/src
#	cd /usr/src
#	git clone https://github.com/zfsonlinux/zfs.git
# and a illumos remote added to it:
#	git remote add illumos https://github.com/illumos/illumos-gate.git

$DEBUG = 0;
$ZFS_SRC_DIR = "/usr/src/zfs";
$MAIL_RECIPIENT = "turbo\@bayour.com";

# ------------------------------------------------

# Go to ZoL source code directory
chdir("$ZFS_SRC_DIR")
    || die("Can't chdir into $ZFS_SRC_DIR, $!\n");
system("git fetch illumos");

# Get the last commit sha1 we checked
open(LATEST, "/var/cache/illumos-gate")
    || die("Can't open latest tag info, $!\n");
$latest = <LATEST>; chomp($latest);
close(LATEST);

# Get all the commits since last check
$i = 0; $j = 0;
open(GIT_LOG, "git log $latest..illumos/master |")
    || die("Can't run git log, $!\n");
while(! eof(GIT_LOG)) {
    my $line = <GIT_LOG>; chomp($line);

    if($line =~ /^commit /) {
	$i++; $j = 0;
	$COMMIT[$i][$j] = $line;
    } else {
	$COMMIT[$i][$j] = $line;
    }

    $j++;
}
close(GIT_LOG);

$ENV{'LOGNAME'} = "Illumos-gate commit watcher";
if(! defined($ENV{'REPLYTO'})) {
    $ENV{'REPLYTO'} = $MAIL_RECIPIENT;
}

# Go through each commit, looking for something that might be
# ZFS related and relevant to ZoL.
for(my $commit_nr = $#COMMIT; $commit_nr > 0; $commit_nr--) {
    $zfs_related = 0;

    my $commit = (split(' ', $COMMIT[$commit_nr][0]))[1];
    open(SHOW, "git show $commit \| $ZFS_SRC_DIR/scripts/zfs2zol-patch.sed \| grep ^diff |")
	|| die("Can't check commit, $!\n");
    while(! eof(SHOW)) {
	$line = <SHOW>; chomp($line);
	next if($line =~ /usr\/src\//);

	$file =  $line;
	$file =~ s/.*\///;

	$fnd = `find $ZFS_SRC_DIR -name $file | wc -l`;
	chomp($fnd);
	next if($fnd == 0);

	$zfs_related = 1;
	last;
    }
    close(SHOW);

    next if(! $zfs_related);

    # Get the mail subject - first line of the body
    for(my $i=4; $COMMIT[$commit_nr][$i]; $i++) {
	if($COMMIT[$commit_nr][$i] =~ /^    [0-9][0-9][0-9][0-9] /) {
	    my $subj = $COMMIT[$commit_nr][$i];
	    $subj =~ s/\"/\\\"/;
	    while($subj =~ s/^\ //) { ; }

	    $SUBJS[$commit_nr] = $subj;
	}
    }

    # Setup mail pipe.
    if(! $DEBUG) {
	open(MAIL, "| mailx -s \"New illumos-gate commit - $SUBJS[$commit_nr]\" $ENV{'REPLYTO'}")
	    || die("Can't pipe to 'mailx', $!\n");
	$fb = MAIL;
    } else {
	$fb = STDOUT;
	print $fb "mailx -s \"New illumos-gate commit - $SUBJS[$commit_nr]\" $ENV{'REPLYTO'}\n";
    }

    # Output the commit message (the mail body).
    my @commit = @{$COMMIT[$commit_nr]};
    for(my $line_nr = 0; $line_nr <= $#commit; $line_nr++) {
	print $fb "    $COMMIT[$commit_nr][$line_nr]\n";
    }
    print $fb "\n";

    # Rest of the mail body - the references to the issue/pull request.
    print $fb "    References:\n";
    $commit = (split(' ', $COMMIT[$commit_nr][0]))[1];
    print $fb "      https://github.com/illumos/illumos-gate/commit/$commit\n";
    for(my $i=0; $SUBJS[$i]; $i++) {
	my $issue = $SUBJS[$i];
	$issue =~ s/\ .*//;
	print $fb "      https://www.illumos.org/issues/$issue\n";
    }

    print $fb "\n";

    close(MAIL) if(!$DEBUG);
}

# Update the 'last illumos commit' sha
if($COMMIT[1][0] && !$DEBUG) {
    my $commit = (split(' ', $COMMIT[1][0]))[1];
    if($commit) {
	open(LATEST, "> /var/cache/illumos-gate")
	    || die("Can't open latest tag info, $!\n");
	print LATEST "$commit\n";
	close(LATEST);
    }
}
