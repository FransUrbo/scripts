#!/usr/bin/perl -w

$DEBUG = 0;
$ZFS_SRC_DIR = "/usr/src/zfs";

chdir("$ZFS_SRC_DIR")
    || die("Can't chdir into $ZFS_SRC_DIR, $!\n");
system("git fetch illumos");

open(LATEST, "/var/cache/illumos-gate")
    || die("Can't open latest tag info, $!\n");
$latest = <LATEST>; chomp($latest);
close(LATEST);

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
$ENV{'REPLYTO'} = "turbo\@bayour.com";

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

    for(my $i=4; $COMMIT[$commit_nr][$i]; $i++) {
	if($COMMIT[$commit_nr][$i] =~ /^    [0-9][0-9][0-9][0-9] /) {
	    my $subj = $COMMIT[$commit_nr][$i];
	    $subj =~ s/\"/\\\"/;
	    while($subj =~ s/^\ //) { ; }

	    $SUBJS[$commit_nr] = $subj;
	}
    }

    if(! $DEBUG) {
	open(MAIL, "| mailx -s \"New illumos-gate commit - $SUBJS[$commit_nr]\" turbo\@bayour.com")
	    || die("Can't pipe to 'mailx', $!\n");
	$fb = MAIL;
    } else {
	$fb = STDOUT;
	print $fb "mailx -s \"New illumos-gate commit - $SUBJS[$commit_nr]\" turbo\@bayour.com\n";
    }

    my @commit = @{$COMMIT[$commit_nr]};
    for(my $line_nr = 0; $line_nr <= $#commit; $line_nr++) {
	print $fb "    $COMMIT[$commit_nr][$line_nr]\n";
    }
    print $fb "\n";

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

if($COMMIT[1][0] && !$DEBUG) {
    my $commit = (split(' ', $COMMIT[1][0]))[1];
    if($commit) {
	open(LATEST, "> /var/cache/illumos-gate")
	    || die("Can't open latest tag info, $!\n");
	print LATEST "$commit\n";
	close(LATEST);
    }
}
