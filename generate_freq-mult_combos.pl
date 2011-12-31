#!/usr/bin/perl -w                                                                                                                  

$FREQ_MIN = 3700;
$FREQ_MAX = 4800;

$BASE_START = 100;
$BASE_END = 600;
$BASE_STEP = 1;

$MULT_START = 4;
$MULT_END = 31.5;
$MULT_STEP = 0.5;

for(my $mult = $MULT_START; $mult <= $MULT_END;) {
    for(my $base = $BASE_START; $base <= $BASE_END;) {
        $freq = sprintf("%0.4d", $base * $mult);
	
        if(($freq >= $FREQ_MIN) && ($freq <= $FREQ_MAX)) {
	    print STDERR "$freq;$base;$mult\n";
	    if(!defined($COMBOS{$freq})) {
		$COMBOS{$freq} = "$base;$mult";
	    }
	}

        $base = $base + $BASE_STEP;
    }
    
    $mult = $mult + $MULT_STEP;
}

for $key (sort keys %COMBOS) {
    print "$key;".$COMBOS{$key}."\n";
}
