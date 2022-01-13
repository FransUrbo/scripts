#!/usr/bin/perl

# Copyrighted according the GPL licence,
# Turbo Fredriksson <turbo@tripnet.se>, 1999/2000.
#
# Use at your own risk...
#
# Usage: create_htmls.pl <VirtualFS> <PicDir> <HtmlDir>
#
#
# Script to create html files with tree frames, side frame where
# directories are shown, and the main frame where the content of
# the directory is shown.
#
# Files must be named '<filename>_<number>.jpg' or '<filename>_<number>.gif'.
# You can rename a bunch of files with the script renumber.pl...
#
# There must be a directory '<whatever>.mini', where the thumbnails are located.
# They can be created with the script create_thumbs.pl.
#
# Usage example: create_htmls.pl --verbose /Pics /home/system/Pics /var/web/pics
#          NOTE: Make sure /home/system/Pics.mini contains the thumbnails created
#                with the create_thumbs.pl script...
#

# Make sure we flush the buffers...
use FileHandle;
STDOUT->autoflush(1);
STDERR->autoflush(1);

use URI::Encode qw(uri_encode);

$verbose        = 0;                                 # Be verbose about actions...
$DEBUG          = 0;                                 # Output the files list (&get_list())
$STDERROR       = 1;                                 # Print debuging info?

$config{background1} = ".bkgrnd.gif";                # Side frame background picture...
$config{background2} = ".pinksilk.gif";              # Main frame background picture...
$config{check_img}   = ".checkbl3.gif";              # 
$config{title}       = "! pictures !";               # Index page title
$config{sideframe}   = "side_frame.html";            # What file for the side frame?
$config{changepass}  = "change_password.html";       # Page where you change your password.
#
$config{mainframe}   = ".right.html";                # What file to use for the initial main frame?
$config{noframes}    = ".noframes.html";             # What file for a non frames enabled browser?

# Pictures / line
$pics_per_line = 8;

# Maximum picture lines / page
$lines_per_page = 8;

# Maximum pics / page
$pics_per_page = $pics_per_line * $lines_per_page;

# Start value...
$base_page_number = "001";
$page = $base_page_number;

# ----------------------------------------------------

# Do we have any arguments?
&check_args();
print "VirtualFS: $virtpicdir, Picdir: $realpicdir,  Html: $htmldir\n\n"
    if($verbose);

# Get the config file in the $htmldir directory
&check_config();

# Create the link to this perlscript in the htmldir...
&create_link();

# Get directory listing...
print "Getting dir list... " if($verbose);
@top = &get_list($realpicdir, "dirs");
print "done.\n" if($verbose);

# Create the index file...
&create_index_file();

# Create all the directory HTML files...
&create_directory_files($realpicdir);

# Create the side frame...
&create_side_frame(@top);

# Create the change password page...
#&create_change_password();

# ----------------------------------------------------

sub check_args {
    my($arg);

    if( $#ARGV >= 2 ) {
	# Ohh yes.... Process it...
	
	foreach $arg (@ARGV) {
	    if( $arg =~ /^\-/ ) {
		if( $arg eq '--help' || $arg eq '-h' || $arg eq '?' ) {
		    &help();
		} elsif( $arg eq '--verbose' || $arg eq '-v' ) {
		    $verbose = 1;
		} elsif( $arg eq '--very-verbose' || $arg eq '-vv' ) {
		    $verbose = 2;
		} elsif( $arg eq '--debug' || $arg eq '-d' ) {
		    $DEBUG = 1;
		}
	    } else {
		if(! $virtpicdir ) {
		    $virtpicdir = $arg;
		} elsif( $virtpicdir && !$realpicdir ) {
		    $realpicdir = $arg;
		} else {
		    $htmldir = $arg;
		}
	    }
	}
    } else {
	&help();
    }

    $virtpicdir =~ s/\/$//;
    $realpicdir =~ s/\/$//;
    $htmldir    =~ s/\/$//;
}

sub check_config {
    my($tmp, $name, $var);

    if( -e "$htmldir/.create_htmls.conf" ) {
	open(CONFIG, "$htmldir/.create_htmls.conf")
	    || die "Could not open $htmldir/.create_htmls.conf, $!\n";
	while(! eof(CONFIG) ) {
	    $tmp = <CONFIG>;
	    chop($tmp);
	    
	    # Skip comments and empty lines...
	    next if( $tmp =~ /^\#/ );
	    next if( $tmp =~ /^$/ );
	    
	    ($name,$var)=split(/=/, $tmp);
	    
	    $var = 'yes' if( $var eq 'true' );
	    $var = 'no'  if( $var eq 'false' );
	    
	    printf("  %-24s = %s\n", $name, $var) if $DEBUG;
	    $config{$name} = $var;
	}

	print "Done reading config...\n\n" if $DEBUG;
	close(CONFIG);
    }
}

sub strip_file {
    local($file) = @_;

    $file =~ s@^/@@;
    $file =~ s@/$@@;

    $file =~ s@/@_@g;
    $file =~ s@^_@@;
    $file =~ s@_$@@;
    $file =~ s@\ @@g;
    $file =~ s@,@@g;
    $file .= "-$page.html";

    return($file);
}

sub create_index_file {
    print " Creating [index] '$htmldir/index.html'... " if($verbose >= 1);

    $OUTPUT = new FileHandle "> $htmldir/index.html";
    die "Could not open '$htmldir/index.html', $!\n" if( !defined $OUTPUT );
    $OUTPUT->autoflush(1);

    print $OUTPUT <<EOF
<html>
  <head><title>$config{title}</title></head>

  <killframe>

  <frameset cols="25%,*" border=0 framespacing="0" noresize>
    <frame src="$config{sideframe}"
           name="directory list" border=1 marginwidth=1 marginheight=0 
           scrolling ="yes" bordersize=0 noresize>
    <frame src="$config{mainframe}"
           name="main"  border=1 marginwidth=1 marginheight=0
           scrolling ="yes" bordersize=0 noresize>

    <noframes>
      <body>
        <p>Sorry, your browser does not support frames...
        <p>Use this <a href="$config{noframes}">link</a> to se the side without frames...
      </body>
    </noframes>
  </frameset>
</html>
EOF
    ;

    $OUTPUT->close;

    print "done.\n" if($verbose >= 1);
}

sub create_side_frame {
    local(@dirlist) = @_;
    my($i, $printed_ft, $printed_subft, $main_dir, $sub_dir, $file, $htmlfile, $picdir, $dir_link, $OUTPUT);
    $page = $base_page_number;

    print " Creating [sideframe] '$htmldir/$config{sideframe}'... " if($verbose >= 1);
    print "\n" if($verbose >= 2);


    $OUTPUT = new FileHandle "> $htmldir/$config{sideframe}";
    die "Could not open '$htmldir/$config{sideframe}', $!\n" if( !defined $OUTPUT );
        $OUTPUT->autoflush(1);


    # Print the HTML header...
    &header("$htmldir/$config{sideframe}");
    print $OUTPUT "  <BODY BACKGROUND=\"$config{background1}\">\n";


    # -------------------------------------------


    # Create the upper part of the side frame...
    for( $i = 0; $dirlist[$i]; $i++ ) {
	$main_dir =  (split('\/', $dirlist[$i]))[0];
	
	$sub_dir  =  $dirlist[$i];
	$sub_dir  =~ s@$main_dir/@@;

	$file  =  "$virtpicdir/$dirlist[$i]";
	$file  =~ s@/@_@g;
	$file  =~ s@^_@@;
	$file  =~ s@_$@@;
	$file  =~ s@_\.@@;
	$file  =~ s@\ @@g;
	$file  =~ s@,@@g;
	$file .=  "-$page.html";

	$output = &get_files_in_dir("$realpicdir/$dirlist[$i]");

	print "  SidePage ($i): $file\t('$realpicdir/$dirlist[$i]')\n" if($DEBUG);
	
	$dir_link =  $main_dir;
	$dir_link =~ s/ - /<br>/g;
	$dir_link => s/, /<br>/g;

	if( $dirlist[$i+1] ) {
	    if( ($dirlist[$i+1] !~ /$main_dir/) && ($dirlist[$i-1] !~ /$main_dir/) ) {
		print "  Adding directory '$main_dir'... " if($verbose >= 2);
		print $OUTPUT <<EOF
    <!-- src location 1 -->
    <table>
      <tr>
        <th><img src="$config{check_img}"></th>
        <th align="left">
          <a href="$file" target="main"
             onMouseOver="window.status='$output pictures in directory $dirlist[$i].'; return true">$dir_link</a>
        </th>
      </tr>
    </table>
EOF
    ;
		print "done.\n" if($verbose >= 2);
	    }
	} else {
	    print $OUTPUT <<EOF
    <!-- src location 2 -->
    <table>
      <tr>
        <th><img src="$config{check_img}"></th>
        <th align="left">
          <a href="$file" target="main"
             onMouseOver="window.status='$output pictures in directory $main_dir.'; return true">$dir_link</a>
        </th>
      </tr>
    </table>
EOF
    ;
	}
	print $OUTPUT "    <p>\n\n";
    }


    # -------------------------------------------


    # Create the bottom part of the side frame...
    print $OUTPUT "    <!--  folder tags -->\n\n    <fl>\n";
    $printed_ft = 0; $printed_subft = 0;

    print STDERR "\n" if($STDERROR);
    for( $i = 0; $dirlist[$i]; $i++ ) {
	printf("  DIRLIST (%.4d): $dirlist[$i]\n", $i) if($DEBUG);
	$main_dir =  (split('\/', $dirlist[$i]))[0];
	
	$sub_dir  =  $dirlist[$i];
	$sub_dir  =~ s@$main_dir/@@;

	$file  =  "$virtpicdir/$dirlist[$i]";
	$file  =~ s@/@_@g;
	$file  =~ s@^_@@;
	$file  =~ s@_$@@;
	$file .=  "-$page.html";
	
	$output = &get_files_in_dir("$realpicdir/$dirlist[$i]");

	if( $dirlist[$i+1] ) {
	    if( ($dirlist[$i+1] =~ /\/.*\//) || ($dirlist[$i] =~ /\/.*\//) ) {
		# Create folder under folder
		$next_dir = (split('\/', $dirlist[$i]))[1];
		print "  Adding NEXTDIR $dirlist[$i+1] ($main_dir.$next_dir) $printed_subft\n" if($DEBUG);

		$next_sub_dir =  $sub_dir;
		$next_sub_dir =~ s@$next_dir/@@;

		if( ($prev_main_dir ne $main_dir) && !$printed_subft ) {
		    print $OUTPUT "        <fl>\n";
		    $prev_main_dir = $main_dir;
		    $printed_subfl = 1;
		}

		if( ($dirlist[$i+1] =~ /$next_dir\//) && ($next_dir ne '.') && !$printed_subft) {
		    print $OUTPUT "          <ft folded>$next_dir\n";
		    $printed_subft = 1;
		}

		$printed_subft = 0 if( $dirlist[$i+1] !~ /$next_dir/ );

		if( ($dirlist[$i+1] =~ /$next_dir/) && ($next_dir ne '.') && $printed_subft && $next_sub_dir) {
		    print $OUTPUT <<EOF
            <FD><a href="$file" target="main"
                   onMouseOver="window.status='$output pictures in directory $main_dir.$sub_dir.'; return true">$next_sub_dir</a>
EOF
    ;
		}

		if( ($dirlist[$i] =~ /$next_dir/) &&
		    ($dirlist[$i] =~ /$next_sub_dir/) &&
		    ($dirlist[$i] =~ /\//) &&
		    !$printed_subft ) {
		    
		    print "  Adding NEXTSUBDIR $next_dir\n" if($DEBUG);
		    print $OUTPUT <<EOF
            <fd><a href="$file" target="main"
                   onMouseOver="window.status='$output pictures in directory $main_dir.$sub_dir.'; return true">$next_sub_dir</a>

EOF
    ;
		    $printed_subft = 0;
		}
	    } else {
		# Create folder under main
		print "  Adding MAINDIR $dirlist[$i+1] ($main_dir) $printed_ft\n" if($DEBUG);

		if( ($dirlist[$i+1] =~ /$main_dir\//) && ($main_dir ne '.') && !$printed_ft) {
		    print $OUTPUT "      <ft folded>$main_dir\n";
		    $printed_ft = 1;
		}
		
		$printed_ft = 0 if( $dirlist[$i+1] !~ /$main_dir/ );
		
		if( ($dirlist[$i+1] =~ /$main_dir/) && ($main_dir ne '.') && $printed_ft && $sub_dir) {
		    if( ($main_dir ne $prev_main_dir) && $printed_subfl ) {
			print $OUTPUT "        </fl>\n\n";
			print $OUTPUT "      <ft folded>$main_dir\n";

			$prev_main_dir = $main_dir; $printed_subfl = 0;
		    }

		    if( $prev_main_dir ) {
			print $OUTPUT <<EOF
              <fD><a href="$file" target="main"
                     onMouseOver="window.status='$output pictures in directory $sub_dir.'; return true">$sub_dir</a>

EOF
    ;
		    } else {
			print $OUTPUT <<EOF
        <fD><a href="$file" target="main"
               onMouseOver="window.status='$output pictures in directory $sub_dir.'; return true">$sub_dir</a>
EOF
    ;
		    }
		}

		if( ($dirlist[$i] =~ /$main_dir/) &&
		    ($dirlist[$i] =~ /$sub_dir/) &&
		    ($dirlist[$i] =~ /\//) &&
		    !$printed_ft ) {
		    
		    print "  Adding SUBDIR $sub_dir\n" if($DEBUG);
		    print $OUTPUT <<EOF
        <Fd><a href="$file" target="main"
               onMouseOver="window.status='$output pictures in directory $sub_dir.'; return true">$sub_dir</a>

EOF
    ;
		    $printed_ft = 0;
		}
	    }
	}
    }

    print $OUTPUT "    </fl>\n";


    # -------------------------------------------


#    print $OUTPUT "<!-- For some reason, this doesn't work as intended...\n";
#
#    # Create the shortcut selector...
#    $picdir =  $virtpicdir; $picdir =~ s@^/@@; $picdir =~ s@/$@@;
#    print $OUTPUT <<EOF
#
#    <center>
#      <form method="post" target="main">
#	Jump to a specified page
#        <select name="Category"
#                class="dropdown"
#                onchange="window.open('Pics' + this.options[this.selectedIndex].value + '.html', 'main')">
#          <option selected value="0">Choose page here
#
#EOF
#    ;
#
#    foreach $htmlfile (sort(@HTML_FILES)) {
#	# .../Pics_Unsorted-105.html
#	$htmlfile =~ s@$htmldir/@@; # Pics_Unsorted-105.html
#	$htmlfile =~ s@.html@@;     # Pics_Unsorted-105
#
#	# ---
#
#	$htmlname = $htmlfile;
#	$htmlname =~ s@_@/@g;
#	$htmlname =~ s@^/@@;
#	$htmlname =~ s@$picdir/@@;
#
#	# ---
#
#	$htmlfile =~ s@$picdir@@;      # _Unsorted-105
#	$htmlfile =~ s@$picdir\_@@;
#
#	print $OUTPUT "          <option value=\"$htmlfile\">$htmlname\n";
#    }
#
#    print $OUTPUT <<EOF
#        </select>
#      </form>
#    </center>
#EOF
#    ;
#
#    print $OUTPUT "-->\n";

#    print $OUTPUT <<EOF
#
#    <center>
#      <a href=change_password.html target=main>Change your password</a>
#    </center>
#
#    <p>
#				
#EOF
#    ;

    # Print the HTML footer...
    &footer();

    $OUTPUT->close;

    print "done.\n" if($verbose >= 1);
}

sub create_change_password {
    print " Creating [changepass] '$htmldir/$config{changepass}'... " if($verbose >= 1);

    $OUTPUT = new FileHandle "> $htmldir/$config{changepass}";
    die "Could not open '$htmldir/$config{changepass}', $!\n" if( !defined $OUTPUT );
        $OUTPUT->autoflush(1);

    # Print the HTML header...
    &header();
    print $OUTPUT "  <BODY BACKGROUND=\"$config{background1}\">\n";

    print $OUTPUT <<EOF
    <pike>
string ret;

if( id->variables->newpass &&
    (id->variables->newpass == id->variables->verpass) ) {
  int err;
  string filter, userdn, pass;
  object con = 0;

  //pass = crypt((id->variables->newpass/"\000")[0]);
  
  // Create object and bind to server
  err = catch(con = Protocols.LDAP.client("localhost"));
  if(err) return "Could not create connection to localhost...";

  err = catch(con->bind());
  if(err) return "Could not bind to LDAP server...";
  
  // Set the search base and scope
  con->set_basedn("dc=papadoc,dc=bayour,dc=com");
  con->set_scope(2);
  
  // Search for the dn...
  object res = con->search("uid="+id->auth[1]);
  
  // Get the UserDN..
  userdn = res->get_dn();

  // -------------------------------------------

  // Set the new search base
  con->set_basedn(userdn);

  // Rebind as the authenticated user...
  if(userdn) {
    err = catch(con->bind(userdn, id->misc->pw));
    if(err) return "Could not rebind as user";

    // Write the new 'userPassword' with the crypted version of 'id->variables->newpass'.
    // 
    //    0, add
    //    1, delete
    //    2, replace

    err = catch(con->modify(userdn,(["userpassword":({2,"{crypt}"+pass})])));

    if(!err) ret = "<center><h1>Good. The password have been changed successfully!!</h1></center><p>";
    else     ret = "<p><center><font color=red>Oups, couldn't update password!</font></center><p>";
  } else
    ret = "Could not find users Distinguished Name...";

  // Unbind from database, and return correct status...
  con->unbind();
  return ret;
} else {
  string filename = "";
  int loaded;

  if(loaded) {
    ret  = "<center>\n"
      "  <font size=+2>Passwords <font color=red>don't match</font>!<br>"
      "Please try again.</font>"
      "</center>";
  }

  ret += "<form method=post action=" + id->not_query + ">"
    "      <table>"
    "        <tr>"
    "          <td><gtext>Username:</gtext></td>"
    "          <td><font color=red>" + id->auth[1] + "</font></td>"
    "        </tr>"
    
    "        <tr>"
    "          <td><gtext>New password:</gtext></td>"
    "          <td><input type=password name=newpass></td>"
    "        </tr>"
    
    "        <tr>"
    "          <td><gtext>Verify password:</gtext></td>"
    "          <td><input type=password name=verpass></td>"
    "        </tr>"
    
    "        <tr>"
    "          <td></td>"
    "          <td><input type=submit value=\\"Set new password\\"></td>"
    "        </tr>"
    
    "      </table>"
    "    </form>";
  
  loaded = 1;
  return ret;
}
    </pike>
  </BODY>
</HTML>

EOF
    ;

    # Print the HTML footer...
    &footer();

    $OUTPUT->close;

    print "done.\n" if($verbose >= 1);
}

sub create_directory_files {
    my($j, $file, $col, $pictures, $dir, $name, $prevdir, $first_table, $newdir, $newfile, @files);

    print " Creating directory pages... " if($verbose >= 1);

    $j = 0; $page = $base_page_number;
    if( $virtpicdir && "$virtpicdir.mini" ) {
	print "Getting file list... " if($verbose >= 2);
	@files = &get_list("$realpicdir.mini", "files");
	print "done.\n" if($verbose >= 2);

	if(! defined($files[0]) ) {
	    print "No thumbnails! Run 'create_thumbs.pl' first!\n";
	    exit(1);
	}

	if( $files[$j+1] && $file[$j] ) {
	    while($files[$j+1] !~ /_[0-9][0-9]/) {
		last if(! $files[$j]);
		print STDERR "  1: $files[$j] : $files[$j+1]\n" if($STDERROR);
		$j++;
	    }
	    print STDERR "  files[$j]='$files[$j]'\n" if($STDERROR);
	}

	# Calculate the name of the first HTML file...
	$file = &strip_file("$virtpicdir/$files[$j]");
	push(@HTML_FILES, $file);

	# Open the first (top) HTML file...
	print STDERR "\n BEGIN: $htmldir/$file\n" if($STDERROR);
	&open_html_file("$htmldir/$file");
	print STDERR "\n" if($STDERROR);

	# Go through each file entry...
	$col = 1; $prevdir = ""; $first_table = 0;
	for($j = 1 ; $files[$j]; $j++ ) {
	    # Do we have an entry (keep perl happy)?
	    if( $files[$j] ) {
		printf(STDERR " FILES (%5s): $files[$j]\n", $j) if($STDERROR);

		# Get the filename from the list...
		($basedir, $file) = &basename($files[$j]);
		
		# Remove the extension...
		$file = (split('\.', $file))[0];

		if(! $file ) {
		    next;
		}
		
		# ---
		
		print STDERR " prev: '$prevdir'; base: '$basedir'; files[$j]: '$files[$j]'\n\n" if($STDERROR);
		if( $files[$j] =~ /\/$/ ) {
		    # We have a new directory...
		    print STDERR "\n <-- new dir (files[$j]='$files[$j]') -->\n" if($STDERROR);
		    
		    $pictures = 0; $col = 1; $page = $base_page_number;

		    # Print the TABLE footer...
		    &table_end();
	
		    # Print the HTML footer...
		    &footer();

		    # Close file...
		    $OUTPUT->close;


		    # Reopen the HTML file with the next number...
		    $file = &strip_file("$virtpicdir/" . (&basename($files[$j]))[0]);
		    push(@HTML_FILES, $file);

		    &open_html_file("$htmldir/$file");
		    print STDERR "\n" if($STDERROR);

		    $first_table = 0;

		    # TODO: Not quite sure why it needs to be '0' here, but if it's '1', then
		    # the very first column will start at '2'!???!! Weird..
		    # Weirder: But this is only on anything but the first file!
		    $col = 0;
		}

		# ---

		# If this is the first image, we start the table here...
		if(! $first_table ) {
		    # Print the first table start...
		    $basedir =~ s@/$@@;
		    print $OUTPUT <<EOF;

    <TABLE>
      <TR ALIGN="center">
        <TD>
          <H1>$basedir</H1>
        <TD>
      </TR>
      <TR>
        <TD WIDTH="500" VALIGN="top">
          <OBOX ALIGN="LEFT" WIDTH="480">
            <TITLE>$basedir</TITLE>
            <TABLE>
              <TR>
EOF
    ;
		    $first_table = 1;
		}
		
		if( $file =~ /\_/ ) {
		    $name =  (split('_', $file))[1];
		} else {
		    $name = $file;
		}

		# Calculate the name of the _NEXT_ HTML file...
		if($files[$j+1]) {
		    $basedir = (&basename("$virtpicdir/$files[$j+1]"))[0];
		    $next = &strip_file($basedir);
		} else {
		    $next  = $file;
		}

		# Print the image...
		if( $files[$j] !~ /\/$/ ) {
		    $size = `ls -l "$realpicdir/$files[$j]"`;
		    $size = (split(' ', $size))[4];

		    my $uri_this = uri_encode("$virtpicdir/$files[$j]");

		    my $uri_next = uri_encode("$virtpicdir/$files[$j+1]");
		    $file_next = (&basename($files[$j+1]))[1];
		    $name_next = (split('\.', $file_next))[0];

		    print $OUTPUT <<EOF;
                <!--- Column no $col. Picture no: $pictures -->
                <TD WIDTH="100%">
                  <CENTER>
                    <IMG SRC=\"$virtpicdir.mini/$files[$j]\" ALT="$file" BORDER="0"
                         onClick="viewLink('$uri_this', '$file', '$uri_next', '$name_next', event)"
                         target="main"><BR>$name
                  </CENTER>
                </TD>
EOF
    ;
		}
		
		# A maximum of X pictures in a line...
		if( ($col == ($pics_per_line - 1)) && ($pictures < ($pics_per_page - 1)) ) {
		    print $OUTPUT <<EOF
              </TR>

              <TR>
EOF
    ;
		    $col = 1;
		} else { 
		    print $OUTPUT "\n";
		    $col++;
		}
		
		# Calculate the file name for the HTML file...
		if( $files[$j+1] ) {
		    $basedir = (&basename("$virtpicdir/$files[$j+1]"))[0];
		} else {
		    $basedir = (&basename("$virtpicdir/"))[0];
		}
		$file = &strip_file($basedir);

		# A maximum of 40 pictures on one page...
		# <IMG SRC=\"$virtpicdir.mini/$files[$j]\" ALT="$file" BORDER=0><BR>$name

		if( $pictures >= ($pics_per_page - 1) ) {
		    $pictures = 0; $col = 1; $page++;
		    $file .= "-$page.html";
		    
		    # Add a link to the next HTML file...
		    print $OUTPUT <<EOF
          </TABLE>
        </OBOX>
      </TD>
    </TABLE>

    <!-- The bottom part of the file -->
    <TABLE>
      <TR>
        <TD ALIGN=LEFT WIDTH="460">
          <FONT SIZE="-1"><A HREF="#Top">Back to top of page</A></FONT>
        </TD>

        <TD ALIGN=RIGHT>
          <FONT SIZE="-1"><A HREF="$file">Next page</A></FONT>
        </TD>
      </TR>
    </TABLE>

    <HR WIDTH="100%">

    <TABLE>
      <TR>
        <TD ALIGN=CENTER WIDTH="460">
          <H6>
            <B>Pages created by a perl script by<BR>Turbo Fredriksson</B>
            <TABLE>
              <TR>
                <TD ALIGN="left" WIDTH="90%">
                  Shift-LMB to download scripts:<br>
                  <A HREF=create_htmls.pl>create_htmls.html</A><br>
                  <A HREF=create_thumbs.pl>create_thumbs.pl</A><br>
                  <A HREF=renumber.pl>renumber.pl</A><br>
                </TD>
                <TD ALIGN="right">
                  View the scripts:<br>
                  <A HREF=create_htmls.html TARGET=main>create_htmls.html</A>
                  <A HREF=create_thumbs.html TARGET=main>create_thumbs.pl</A>
                  <A HREF=renumber.html TARGET=main>renumber.pl</A>
                </TD>
              </TR>
            </TABLE>
          </H6>
        </TD>
      </TR>
    </TABLE>
  </BODY>
</HTML>
EOF
    ;

		    # Reopen the HTML file with the next number...
#		    $OUTPUT->close;
#		    print STDERR " HTML FILE(1):  $htmldir/$file\n" if($STDERROR);
#		    push(@HTML_FILES, $file);
#		    &open_html_file("$htmldir/$file");

		    $first_table = 0; 
		} else {
		    $file .= "-$page.html";

		    $pictures++;
		}

		last if(!$files[$j+1]);

		$prevdir = $basedir;
	    } # if($files[$j])
	} # for(;$files[$j];$j++) 

	# Print the TABLE footer...
	&table_end();
	
	# Print the HTML footer...
	&footer();

	$OUTPUT->close;
	print "done.\n" if($verbose >= 1);
    }
}

sub create_link {
    my($tmp);

    $tmp =  $virtpicdir;
    $tmp =~ s/^\///;

    if( -e "$htmldir" ) {
	print "Cleaning up '$htmldir'... " if($verbose >= 1);
	system("cd '$htmldir' && rm -f *.html $tmp $tmp.mini");
	system("cd '$htmldir' && rm -f $tmp $tmp.mini");
	print "done.\n" if($verbose >= 1);

#	print "Creating program links... " if($verbose >= 1);
#	system("cd '$htmldir' && ln -sf $realpicdir $tmp");
#	system("cd '$htmldir' && ln -sf $realpicdir.mini $tmp.mini");
#
#	system("cd '$htmldir' && ln -sf ~/bin/create_htmls.pl create_htmls.pl");
#	system("cd '$htmldir' && ln -sf ~/bin/renumber.pl renumber.pl");
#	system("cd '$htmldir' && ln -sf ~/bin/create_thumbs.pl create_thumbs.pl");
#	print "done.\n" if($verbose >= 1);
#
#	print "Converting perlscripts to html ... " if($verbose >= 1);
#	system("cd '$htmldir' && code2html.pl perl create_htmls.pl create_htmls.html");
#	system("cd '$htmldir' && code2html.pl perl renumber.pl renumber.html");
#	system("cd '$htmldir' && code2html.pl perl create_thumbs.pl create_thumbs.html");
#	print "done.\n" if($verbose >= 1);
    } else {
	mkdir("$htmldir", 0755);
    }
}

# ----------------------------------------------------

sub get_list {
    local($dir, $type) = @_;
    my(%DIRS, @TMP, $LINE, $directory, $i);

    # Check to see if the directory exists...
    if( -e "$dir" ) {
	# Open the directory...
	if( $type eq 'dirs' ) {
	    open(LIST, "cd '$dir' \&\& /usr/bin/find -type d |");
	} else {
#	    print "DEBUG: dir='$dir'\n";
	    $dir_name    = (&basename($dir))[0];

#	    print "DEBUG: cd '$dir/..' && /usr/bin/find '$dir_name' -type f\n";
#	    open(LIST, "cd '$dir/..' \&\& /usr/bin/find '$dir_name' -type f |");

#	    print "DEBUG: cd '$dir' && /usr/bin/find -type f\n";
	    open(LIST, "cd '$dir' \&\& /usr/bin/find -type f |");
	}

	print "\n" if( $DEBUG );
	while(! eof(LIST) ) {
	    $LINE = <LIST>;
	    chomp($LINE);

	    next if( $LINE =~ /xvpics/ );

	    $LINE =~ s@\./@@;
	    $LINE =~ s@$dir_name/@@;

	    print "  input:   $LINE\n" if( $DEBUG );
	    push(@TMP, $LINE);
	}
	close(LIST);
    } else {
	die "Directory $dir does not exists!\n";
    }


    # Prepare a sort of the list...
    for($i = 0; $TMP[$i]; $i++ ) {
	$DIRS{$TMP[$i]} = "$TMP[$i]";
	print "  prepare: $DIRS{$TMP[$i]}\n" if( $DEBUG );
    }
    
    
    undef @TMP;
    foreach $directory (sort(keys %DIRS)) {
	if( $type eq 'files' ) {
	    # The actual directory must be before the real file...
	    if( $directory =~ / - 001/ ) {
#		printf "DEBUG: DIRS{$directory}='$DIRS{$directory}' (" . (split('/', $DIRS{$directory}))[0] . ")\n";
		push(@TMP, (split('/', $DIRS{$directory}))[0] . '/');
	    }
	}
	push(@TMP, $DIRS{$directory});
	
	print "  sorted:  $DIRS{$directory}\n" if( $DEBUG );
    }

    return(@TMP);
}

sub get_files_in_dir {
    local($dir) = @_;
    my($output);

    open(SIZE, "cd \"$dir\"; /bin/ls -l \| /usr/bin/wc -l |")
	|| die "Could not open SIZE in $dir, $!\n";
    $output = <SIZE>;
    close(SIZE);

    chomp($output);
    $output =~ s/\ //g;
    $output--;

    return($output);
}

sub basename {
    my($line) = @_;
    my(@path, @result, $dir, $i, $file);

    $line =~ s@//@/@g;

#    print "LINE: $line\n";
    @path = split('/', $line);

    for($i = 0; $path[$i+1]; $i++) {
#	print "path[$i]: '$path[$i]'\n";
	$dir .= $path[$i];

	if( $path[$i+1] ) {
	    $dir .= "/";
	}
    }
#    print "path[$i]: '$path[$i]'\n";
    $file = $path[$i];

    # We have path and a file name...
#    print "$dir : $file\n";

    $dir  =  "$line"  if(! $dir );
    $file =  "$line)" if(! $file );

    $dir  =~ s@_$@@;

    push @result, $dir;
    push @result, $file;

    return(@result);
}

sub open_html_file {
    local($file) = @_;

    print " Creating [html] $file... " if($verbose >= 2);

    $OUTPUT = new FileHandle "> $file";
    die "Could not open '$file', $!\n" if( !defined $OUTPUT );
    $OUTPUT->autoflush(1);

    # Print the HTML header...
    &header($file);

    # Print the java script...
    &javascript($file);
}

# ----------------------------------------------------

sub header {
    local($file) = @_;

    print $OUTPUT <<EOF;
<HTML>
  <HEAD>
    <TITLE>Pics in $virtpicdir</TITLE>
    <META NAME="Author" CONTENT="Script by Turbo Fredriksson">
  </HEAD>
  <!-- $file -->

EOF
    ;
}

sub footer {
    print $OUTPUT <<EOF;

    <!-- The bottom part of the file -->
    <CENTER>
      <FONT SIZE="-5"><A HREF="#Top">Back to top of page</A><BR></FONT>
      <H6>
        <B>Pages created by a perl scripts by Turbo Fredriksson</B>
        <!--
        <TABLE>
          <TR>
            <TD ALIGN="left" WIDTH="90%">
              Shift-LMB to download scripts:<br>
              <A HREF=create_htmls.pl>create_htmls.html</A><br>
              <A HREF=create_thumbs.pl>create_thumbs.pl</A><br>
              <A HREF=renumber.pl>renumber.pl</A><br>
            </TD>
            <TD ALIGN="right">
              View the scripts:<br>
              <A HREF=create_htmls.html TARGET=main>create_htmls.html</A>
              <A HREF=create_thumbs.html TARGET=main>create_thumbs.pl</A>
              <A HREF=renumber.html TARGET=main>renumber.pl</A>
            </TD>
          </TR>
        </TABLE>
        -->
      </H6>
    </CENTER>
  </BODY>
</HTML>
EOF
    ;
}

sub table_end {
    print $OUTPUT <<EOF;
              </TR>
          </TABLE>
        </TD>
      </TR>
    </TABLE>
EOF
    ;
}

sub javascript {
    local($file) = @_;
    $file =~ s/$htmldir//g;
    $file =~ s/^\///g;

    print $OUTPUT <<EOF;
  <SCRIPT LANGUAGE="javascript">
  function viewLink(file, name, next, name_next, evnt) {
    var body="BODY BACKGROUND=$config{background2}"
  
    if (! evnt.modifiers ) {
      document.open("text/html");
      document.writeln("<" + body + ">");

      // Table start
      document.write('<TABLE>\\n');
      document.write('  <TR>\\n');

      // Left link
      document.write('    <TD ALIGN="left" WIDTH="100%">\\n');
      document.write("      <A HREF=$file>Back</A>");
      document.write('    </TD>\\n\\n');

// Just can't get these to work. I get the 'next' picture alone, not as a HTML pages (with more back/next links).
//      // Right link
//      document.write('    <TD ALIGN="right" WIDTH="100%">\\n');
//      document.write('      <A HREF=' + next + '>Next</A>');
//      document.write('    </TD>\\n');

      // Table end
      document.write('  </TR>\\n');
      document.write('</TABLE>\\n\\n');

      // Bottom part of picture page
      document.write('<CENTER>\\n');
      document.write('  <H2>' + name + '</H2>\\n');
      document.write('  <IMG SRC="' + file + '" WIDTH="100%" HEIGHT="100%"><P>\\n');
//      document.write('  <IMG SRC="' + file + '" WIDTH="100%" HEIGHT="100%"');
//      document.write('       onClick="viewLink(' + next + ', ' + name_next + ', uri_next_next, name_next_next, event)"><P>\\n');
      // document.write('  <B>Here we could add some commersial banners etc...</B><P>\\n');
      document.write('</CENTER>\\n');
  
      document.close();
    }
  }
  </SCRIPT>

EOF

    print $OUTPUT "  <BODY BACKGROUND=\"$config{background2}\">";
    ;
}

sub help {
    print "usage: create_htmls.pl [OPTION] <virtpicdir> <realpicdir> <htmldir>\n";
    print "       Create html files in <htmldir>, from the pictures in <realpicdir>\n\n";

    print "  Required parameters:\n";
    print "       virtpicdir     Where the pictures reside in the virtual file system.\n";
    print "       realpicdir     Where the pictures reside in the real file system.\n";
    print "       htmldir        Where the htmlfiles reside in the real file system.\n";
    print "  Where OPTION could be:\n";
    print "       --help, -h, ?  To get this output\n";
    print "       --verbose, -v  No output what so ever (exept errors)\n";
    print "       --debug, -d    Print some debuging output\n";
    exit( 0 );
}
