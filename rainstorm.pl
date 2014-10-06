#!/usr/bin/env perl
use warnings;
use strict;
use Text::Wrap qw(wrap $columns);
use Tk;

my $xorhash = 0;

my %w = (
	mw => new MainWindow( -title => 'IDS RainStorm' ),
);

my %c = (
	background => 'grey30',
	background2 => 'grey20',
	background3 => 'grey25',
	foreground => 'white',
	font_small => '-schumacher-clean-medium-r-normal--6-60-75-75-c-40-iso646.1991-irv',
	font_medium => '-schumacher-clean-medium-r-normal--10-60-75-75-c-40-iso646.1991-irv',
	font_large => '-schumacher-clean-medium-r-normal--14-60-75-75-c-40-iso646.1991-irv',
);

$w{mw}->setPalette( background => $c{background2}, 
	foreground => $c{foreground}, 
	activeBackground => $c{background2},
	activeForeground => $c{background} );

my @subnets = (  "40.9.0.0/16", "42.251.0.0/16", "111.121.128.0/17", "39.227.15.0/24" );
my @subnetint;
my @subnetmask;

my %o = (
	maincanvas => {
		width         => (72*8)+(2*10),
		height        => (256*3)+(2*10),
		margin_top    => 10,
		margin_bottom => 10,
		margin_left   => 10,
		margin_right  => 10,
	},
	zoomcanvas => {
		dx            => 10*72,
		dy            => 256*3,
		width         => (10*72)+(2*10)+(2*100),
		height        => (256*3)+(2*10),
		margin_top    => 10,
		margin_bottom => 10,
		margin_left   => 10,
		margin_right  => 10,
		label_left    => 100,
		label_right   => 100,
	},
	subnets    => \@subnets,
	timespan   => ( 24*60*60 ),
	colwidth   => 72,
	num_cols   => 8,
	winwidth   => 72,
	colheight  => undef,
	totalips   => undef,
	ips_row    => undef,
	ips_cols   => undef,
	winheight  => undef,
	current    => 'all',
	timewin    => 24,
	timestart  => 0,
	ipwin      => 256,
	ipstart    => undef,
	zoom       => 1,
);

die "Usage: $0 <binlogfile>\n" unless @ARGV;
die "$!\n" unless open ALARMINFO, "alarminfo.txt";
die "$!\n" unless open BINFILE, $ARGV[0];
binmode(BINFILE);

$o{totalips} = countips( @{$o{subnets}} );
$o{colheight} = ( $o{maincanvas}->{height} 
		- $o{maincanvas}->{margin_top} 
		- $o{maincanvas}->{margin_bottom}
	); 
$o{ips_cols} = $o{totalips} / $o{num_cols};
$o{ips_row} = $o{ips_cols} / $o{colheight};
$o{ipstart} = off2ip( 0 );

$w{f1} = $w{mw}->Frame()->pack( );
# create frame
$w{c1} = $w{f1}->Canvas( -width => $o{maincanvas}->{width},
	-height => $o{maincanvas}->{height}, 
	-scrollregion => [ 0, 0, $o{maincanvas}->{width}, 
	$o{maincanvas}->{height} ] )->pack();
# create border box
$w{c1}->createRectangle( 
	$o{maincanvas}->{margin_left}, 
	$o{maincanvas}->{margin_top},
	$o{maincanvas}->{width} - $o{maincanvas}->{margin_right}, 
	$o{maincanvas}->{height} - $o{maincanvas}->{margin_bottom}, 
	-fill => 'black', -outline => 'grey90' );
# draw IP colums
for my $i ( 1..$o{num_cols} ) {
	$w{c1}->createLine(
		$o{maincanvas}->{margin_left} + ( $i * $o{colwidth} ),
		$o{maincanvas}->{margin_top} + 1,
		$o{maincanvas}->{margin_left} + ( $i * $o{colwidth} ),
		$o{maincanvas}->{height} - $o{maincanvas}->{margin_bottom},
		-fill => 'grey30' );
}
# draw subnet dividers
for my $i ( 1.. $#{$o{subnets}} ) {
	drawipline( (split /\//, $o{subnets}->[$i])[0] );
}
# calculate the size of the selector box
$o{winheight} = 256 / $o{ips_row};
# create the selector box
$w{c1}->createRectangle( $o{maincanvas}->{margin_left}, $o{maincanvas}->{margin_top},
	$o{maincanvas}->{margin_left} + $o{winwidth}, 
	$o{maincanvas}->{margin_top} + $o{winheight},
	-tags => [ 'window' ], -outline => 'red', -width => 2,
);
# create selector box labeling
$w{c1}->createText( $o{maincanvas}->{margin_left} + ($o{winwidth}/2), $o{maincanvas}->{margin_top},
	-text => int2ip( off2ip( 0 ) ), -anchor=>'s', -tags=>['wintitle'], -fill => 'grey50', );
# track mouse button state
$w{mb} = 0;
# bind the mouse button release event
$w{c1}->bind( 'all', '<ButtonRelease>', [ \&buttonrelease, Ev('x'), Ev('y') ] );
# bind the mouse motion event
$w{c1}->bind( 'all', '<Motion>', [ \&motion, Ev('x'), Ev('y') ] );
# bind the mouse button click
$w{c1}->bind( 'all', '<1>', [ \&mouseclick, Ev('x'), Ev('y') ] );

$w{mw}->bind( '<Control-q>', sub { exit(); } );
$w{mw}->bind( '<Key-a>' => [ \&showalarms, 'all' ] );
$w{mw}->bind( '<Key-r>' => [ \&showalarms, 'red' ] );
$w{mw}->bind( '<Key-g>' => [ \&showalarms, 'green' ] );
$w{mw}->bind( '<Key-y>' => [ \&showalarms, 'yellow' ] );
$w{mw}->bind( '<Key-A>' => [ \&showalarms, 'all' ] );
$w{mw}->bind( '<Key-R>' => [ \&showalarms, 'red' ] );
$w{mw}->bind( '<Key-G>' => [ \&showalarms, 'green' ] );
$w{mw}->bind( '<Key-Y>' => [ \&showalarms, 'yellow' ] );

#######   READ IN ALARM DESCRIPTIONS   #######
my %alarminfo;
$columns = 30;
while ( my $line = <ALARMINFO> ) {
	chomp( $line );
	next unless $line =~ /\w/;
	my ( $id, $short, $long ) = split( /\t/, $line );
	$alarminfo{$id} = "Alarm type: $short";#.(defined($long))?$long:$short;
	$alarminfo{$id} = wrap( "", "", $alarminfo{$id} );
}
close (ALARMINFO);

#######   READ IN ALARMS   #######
my %ips;
my $buffer;
while ( read( BINFILE, $buffer, 16 ) ) {
	my ( $time, $alarm, $badip, $goodip ) = unpack( "V4", $buffer );
	drawalarm( $time, $alarm, $badip, $goodip );
}
close BINFILE;

# start the GUI
MainLoop();

# keep track of mouse button state
sub buttonrelease {
	$w{mb} = 0;
	$w{c1}->itemconfigure( 'window', -outline => 'red' );
}

# when the mouse is clicked on the main canvas, open the zoom (unless it's already
# open).
sub mouseclick {
	my ( $c, $mx, $my ) = @_;
	$w{mb} = 1;
	$w{c1}->itemconfigure( 'window', -outline => 'cyan' );
	$o{startoff} = $o{offset};
	# evil line, returns don't matter, just wanted a one-liner
	return drawAlarms() if defined( $w{tl} );
	$w{tl} = $w{mw}->Toplevel( -title => 'RainStorm Zoom' );
	$w{tl}->bind( '<Control-q>', sub { exit(); } );
	$w{tl}->bind( '<Control-w>', sub { $w{tl}->destroy(); } );
	$w{tl}->bind( '<Destroy>', sub { $w{tl} = undef; } );
	$w{tl}->bind( '<Key-a>' => [ \&showalarms, 'all' ] );
	$w{tl}->bind( '<Key-r>' => [ \&showalarms, 'red' ] );
	$w{tl}->bind( '<Key-g>' => [ \&showalarms, 'green' ] );
	$w{tl}->bind( '<Key-y>' => [ \&showalarms, 'yellow' ] );
	$w{tl}->bind( '<Key-A>' => [ \&showalarms, 'all' ] );
	$w{tl}->bind( '<Key-R>' => [ \&showalarms, 'red' ] );
	$w{tl}->bind( '<Key-G>' => [ \&showalarms, 'green' ] );
	$w{tl}->bind( '<Key-Y>' => [ \&showalarms, 'yellow' ] );

	my $f = $w{tl}->Frame()->pack();
	$w{c2} = $f->Canvas( -width => $o{zoomcanvas}->{width},
		-height => $o{zoomcanvas}->{height},
		-scrollregion => 
			[ 0, 0, $o{zoomcanvas}->{width}, $o{zoomcanvas}->{height}, ]
	)->pack();
	$w{tl}->bind( '<Button-4>' => sub { 
			$o{startoff} -= 10/$o{totalips}; 
			$o{startoff} = 0 if ($o{startoff} < 0);
			drawAlarms();
		} );
	$w{tl}->bind( '<Button-5>' => sub { 
			$o{startoff} += 10/$o{totalips}; 
			$o{startoff} = 1 if ($o{startoff} > 1);
			drawAlarms();
		} );
	$o{ipstart} = off2ip($o{offset});
	$o{ipwin} =  256;
	$o{timewin} = 24;
	$o{timestart} = 0;
	$o{zoom} = 1;
	drawAlarms();
}

# move the red window square and update the text over it with the current IP selected
# update the zoomed window if the mouse button is pressed
sub motion {
	my ( $c, $mx, $my ) = @_;
	# if the mouse Y is too high, clips, too low, clips, otherwise returns mouse Y.
	my $col = int( ( $mx - $o{maincanvas}->{margin_left} ) / $o{colwidth} );
	$col = 0 if $col < 0;
	$col = $o{num_cols}-1 if $col > ($o{num_cols}-1);
	my $dh = $o{maincanvas}->{height} - $o{maincanvas}->{margin_bottom} - $o{maincanvas}->{margin_top};
	my $coloff = ( $my - $o{maincanvas}->{margin_top} - ($o{winheight}/2) ) / $dh;
	$coloff = 0 if $coloff < 0;
	$coloff = 1 - ($o{winheight}/$dh) if $coloff > 1 - ($o{winheight}/$dh);
	$o{offset} = ($col+$coloff)/$o{num_cols};
	my $y = $o{maincanvas}->{margin_top} + ($dh*$coloff);
	my $x = $o{maincanvas}->{margin_left} + ( $o{colwidth} * $col );
	$c->coords( 'window', $x, $y, $x + $o{winwidth}, $y + $o{winheight} );
	$c->coords( 'wintitle', $x + ($o{winwidth}/2), $y );
	$c->itemconfigure( 'wintitle', -text => int2ip( off2ip( $o{offset} ) ) );
	# draw the alarms if the mouse button is pressed and there is a zoom window
	$o{startoff} = $o{offset} if ( $w{mb} && defined( $w{tl} ) );
	if ( $w{mb} && defined( $w{tl} ) ){
		$o{ipstart} = off2ip($o{offset});
		drawAlarms() ;
	}
}
# this draws the alarms on the zoom view
sub drawAlarms {
	# TODO: avoid deleting constant figures
	$w{c2}->delete( 'all' );
	# Draw bounding box
	$w{c2}->createRectangle( 
		$o{zoomcanvas}->{margin_left}, $o{zoomcanvas}->{margin_top},
		$o{zoomcanvas}->{width} - $o{zoomcanvas}->{margin_right}, 
		$o{zoomcanvas}->{height} - $o{zoomcanvas}->{margin_bottom},
		-fill => 'black', -outline => 'grey90', -tags => [ 'backboard' ] );
	# when the mouse goes over the backboard, then remove the alarmbox and kill any 
	# timers for showing an alarmbox
	$w{c2}->bind( 'backboard', '<Enter>' => 
		sub{ 
			# delete the alarmbox if it exists
			$w{c2}->delete('alarmbox') if ( $w{c2}->type('alarmbox') ); 
			# kill any timers for showing an alarmbox
			$w{mw}->afterCancel($w{ti});
		}
	);
	$w{c2}->bind( 'backboard', '<1>' => [ \&zoomOut ] );
	my $xoff = $o{zoomcanvas}->{margin_left} + $o{zoomcanvas}->{label_left};

	if ( $o{timewin} + $o{timestart} > 24 ) {
		warn "Bad time values $o{timewin} $o{timestart}\n";
		$o{timestart} = 24 - $o{timewin};
	}

	# For the zoom, we want to view only the calculated time frame and
	# increase incremental labeling
	# zoom = 1, line for each hour, label for each 6th hour (24 hours)
	# zoom = 2, line for each half hour, label for each 3rd hour (12 hours)
	# zoom = 4, line for each quarter hour, label for each hour (6 hours)
	# zoom = 8, line for each 10 minutes, label for each half hour (3 hours)
	# zoom = 16, line for each 5 minutes, label for each quarter hour (1 hour)
	my ( $timespan, $timehop, $timelabel, $ipspan, $iphop, $iplabel );
	if ( $o{timewin} <= 24 and $o{timewin} > 12 ) {
		$timespan  = 24;
		$timehop   = 1;
		$timelabel = 6;
		$ipspan    = 256;
		$iphop     = 1;
		$iplabel   = 16;
	} elsif ($o{timewin} <= 12 and $o{timewin} > 6 ) {
		$timespan  = 12;
		$timehop   = 1/2;
		$timelabel = 3;
		$ipspan    = 128;
		$iphop     = 1;
		$iplabel   = 8;
	} elsif ($o{timewin} <= 6 and $o{timewin} > 3 ) {
		$timespan  = 6;
		$timehop   = 1/4;
		$timelabel = 1;
		$ipspan    = 64;
		$iphop     = 1;
		$iplabel   = 4;
	} elsif ($o{timewin} <= 3 and $o{timewin} > 1 ) {
		$timespan  = 3;
		$timehop   = 1/6;
		$timelabel = 1/2;
		$ipspan    = 32;
		$iphop     = 1;
		$iplabel   = 2;
	} else {
		$timespan  = 1;
		$timehop   = 1/16;
		$timelabel = 1/4;
		$ipspan    = 16;
		$iphop     = 1;
		$iplabel   = 1;
	}
	my $lines     = $timespan / $timehop;
	my $labelmod  = $timelabel / $timehop; 
	my $scalex    = $timespan / $o{timewin};
	my $dx        = $o{zoomcanvas}->{dx};
	my $xhop      = $dx * $scalex / $lines;
	my $scaley    = $ipspan / $o{ipwin};
	my $dy        = $o{zoomcanvas}->{dy};
	my $yhop      = $dy * $scaley / $ipspan;
	
	#print ( "timewin: $o{timewin}, timestart: $o{timestart}, lines: $lines, labelmod: $labelmod, scalex: $scalex, xhop: $xhop\n" );
	# Draw lines $timehop hours
	my $i = 0;
	for ( my $x = $xoff; $x <= $xoff + $dx; $x += $xhop ) {
		my $time = $o{timestart} + ( $i*$timehop );
		my $color = 'grey20';
		if ( $i % $labelmod == 0 ) {
			$w{c2}->createText( $x, $o{zoomcanvas}->{margin_top}, -anchor => 's',
			-fill => 'white', -text => pod2str($time),
			-font => $c{font_medium} );
			$color = 'grey50';
		}
		$w{c2}->createLine( $x, $o{zoomcanvas}->{margin_top}+1,
			$x, $o{zoomcanvas}->{margin_top} + $o{zoomcanvas}->{dy}, 
			-fill => $color, -dash => '.' );
		$i++;
	}		

	# ball radius
	my $r = 4;

	$i = 0;
	# for each ip to be drawn on this screen
	for ( my $y = $o{zoomcanvas}->{margin_top}; $y < $o{zoomcanvas}->{margin_top} + $dy; $y += $yhop ) {
		if ( $i % $iplabel == 0 && $i != 0 ) {
			$w{c2}->createText( $o{zoomcanvas}->{margin_left} + 97, $y, 
				-anchor => 'e', -text => int2ip( $o{ipstart}+$i ), -fill => 'grey60',
				-font => $c{font_medium} );
			$w{c2}->createLine( $o{zoomcanvas}->{margin_left} + 101, $y,
				$o{zoomcanvas}->{margin_left} + 100 + $dx, $y, -fill => 'grey20',
				-dash => '.' );
		}
		$i++;
		next unless( defined ( $ips{($o{ipstart}+$i-1)} ) );
		$i--;
		foreach my $alarmvec ( @{$ips{($o{ipstart}+$i)}} ) {
			my $hour = timeToHourFraction( $alarmvec->[0] );
			#print ( "Is $hour between $o{timestart} and ", $o{timestart} + $o{timewin},".\n" );
			next if $hour < $o{timestart};
			next if $hour > $o{timestart} + $o{timewin};
			my $x = $xoff + ( ( ($hour - $o{timestart})/$o{timewin}) * $dx );
			#print ( int2ip($o{ipstart}+$i), " $hour maps to $x, $y\n" );
			my $tag = join(":", @{$alarmvec} );
			#calculate percent of total ipspace
			my $attacker = ($alarmvec->[2] == $o{ipstart}+$i)?$alarmvec->[3]:$alarmvec->[2];
			my $first = ($alarmvec->[2] == $o{ipstart}+$i)?'first':'last';
			my $poip = $attacker/(2**32);
			#calculate the origin on the right-y axis
			my $y2 = $o{zoomcanvas}->{margin_top} + ($poip*$o{zoomcanvas}->{dy});
			# if there was another ip specified
			my $color = alarm2color($alarmvec->[1]);
			my $state = ($o{current} eq 'all')?'normal':($color eq $o{current})?'normal':'hidden';
			if ($poip != ($xorhash/(2**32))) {
				# draw a line from the alarm to the 32-bit address space on the right
				$w{c2}->createLine( $x, $y, $xoff+$o{zoomcanvas}->{dx}, $y2,
					-dash => '.', -fill => 'darkcyan', -arrow => $first,
					-activedash => '-', -activefill => 'cyan', 
					-tags => [ $tag, $color ], -state => $state );
				# select all the labels where I want to place my new label
				my @items = $w{c2}->find( 'overlapping', 
					$xoff + $o{zoomcanvas}->{dx} + 3, $y2-5,
					$xoff + $o{zoomcanvas}->{dx} + 53, $y2+5 );
				# grey out each label	
				foreach my $item ( @items ) {
					if ( $w{c2}->type( $item ) eq 'text' ) {
						$w{c2}->itemconfigure( $item, -fill => 'grey30' );
					}
				}
				# add my label
				$w{c2}->createText( $xoff+$o{zoomcanvas}->{dx}+3, $y2, -anchor => 'w',
					-fill => 'grey80', -font => $c{font_medium}, 
					-text => int2ip($attacker),
					-activefill => 'white', -tags => [ $tag, $color ], 
					-state => $state );
			}
			# draw the alarm
			$w{c2}->createOval( $x-$r, $y-$r, $x+$r, $y+$r, -fill => $color, 
				-width => 1, -tags => [ $tag, $color ], -outline => 'grey30', 
				-activeoutline => 'white', -state => $state );
			# bind an event to draw an alarm box when the mouse hovers over the 
			# alarm oval, the connecting line, or the other ip.
			$w{c2}->bind( $tag, '<Enter>' => [ \&displayAlarmBox, $tag, Ev('x'), Ev('y') ] );	
			$w{c2}->bind( $tag, '<1>' => [ \&zoomAlarm, $tag, $o{ipstart}+$i, $alarmvec->[0], Ev('x'), Ev('y') ] );
		}
		$i++;
	}
}

# this draws the alarm details when the mouse hovers over an alarm in the zoom view
sub displayAlarmBox {
	my ( $c, $t, $x, $y ) = @_;

	my @alertvec = split( /:/, $t );
	my @extralines = split( /\n/, $alarminfo{$alertvec[1]} );
	my $ec = $#extralines;
	my $text = $alarminfo{$alertvec[1]} ."\n"
		."Occured: ".join(":", reverse((localtime($alertvec[0]))[0..2]))."\n"
		."Source: ".int2ip($alertvec[2])."\n"
		."Destination: ".int2ip($alertvec[3]);
	my $dx = 720;
	my $dy = 768;
	if ( $y+60+($ec*14) > $dy + $o{maincanvas}->{margin_top} + $o{maincanvas}->{margin_bottom} ) {
		$y = $dy + $o{maincanvas}->{margin_top} + $o{maincanvas}->{margin_bottom} - ( 60+($ec*14) );
	}
	if ( $x+180 > $o{maincanvas}->{margin_left} + $o{maincanvas}->{margin_right} + 920 ) {
		$x = $o{maincanvas}->{margin_left} + $o{maincanvas}->{margin_right} + 920 - 180;
	}
	$w{ti} = $w{mw}->after( 650, sub { $c->createRectangle( $x+3, $y, $x+180, $y+60+($ec*14), -fill => 'goldenrod', 
		-outline => 'FloralWhite', -tags => [ 'alarmbox' ], );
		$c->createText( $x+5, $y+2, -anchor => 'nw', -fill => 'black', 
		-text => $text, -tags => [ 'alarmbox' ], ); } );
}

sub zoomAlarm {
	my ( $c, $tag, $ip, $time, $x, $y ) = @_;
	# right now the IP/time ratio is 256 ips over 24 hours
	# when we zoom, we wish to keep the same ratio, but just view less data
	# e.g. 128 ips  over 12 hours, 64 ips over 6 hours, 32 ips over 3 hours
	# 16 ips over 1 1/2 hours
	#$w{c2}->itemconfigure( $tag, -outline => 'orange', -width => 2 );
	centerPan( $y );
	return if ( $o{zoom} == 16 );
	my $targetzoom = $o{zoom}*2;
	my $oldzoom = $o{zoom};
	my ( $xhalf, $yhalf ) = ( ( $x > $o{zoomcanvas}->{width}/2 ), ( $y > $o{zoomcanvas}->{height}/2 ) );
	my $oldstarttime = $o{starttime};
#	for( my $zoom = $o{zoom}; $zoom <= $targetzoom; $zoom += ($targetzoom - $oldzoom)/10 ) {
#		$o{zoom}      = $zoom;
#		$o{ipstart}   = int( $ip - ( 128 / $zoom ) );
#		$o{ipwin}     = int( 256 / $zoom );
#		my $hour      = int( timeToHourFraction( $time ) );
#		$o{timewin}   = ($zoom<16)?24/$zoom:1;
#		$o{timestart} = ($xhalf==0)?$hour - ( $hour % $o{timewin} ):$oldstarttime + 24/$oldzoom - timeToHourFraction( $time );
#		drawAlarms();
#		$w{mw}->update();
#		select( undef, undef, undef, 1/200 );
#	}
	$o{zoom}      = $targetzoom;
	$o{ipstart}   = int( $ip - ( 128 / $targetzoom ) );
	$o{ipwin}     = int( 256 / $targetzoom );
	my $hour      = int( timeToHourFraction( $time ) );
	$o{timewin}   = ($targetzoom<16)?24/$targetzoom:1;
	$o{timestart} = $hour - ( $hour % $o{timewin} );
	drawAlarms();
	$w{mw}->update();
	#$w{mw}->after( 300 => sub{ $w{c2}->itemconfigure( $tag, -outline => 'black', -width => 1 ); } );
}

sub zoomOut {
	return if ( $o{zoom} == 1 );
	my $targetzoom = $o{zoom}/2;
	my $oldzoom = $o{zoom};
	my $ip = $o{ipstart} + ( 128 / $o{zoom} );
	my $time = $o{timestart};
	$o{zoom}      = $targetzoom;
	$o{ipstart}   = int( $ip - ( 128 / $targetzoom ) );
	$o{ipwin}     = int( 256 / $targetzoom );
	my $hour      = int( timeToHourFraction( $time ) );
	$o{timewin}   = ($targetzoom<16)?24/$targetzoom:1;
	drawAlarms();
	$w{mw}->update();
}

sub centerPan {
	my ( $y ) = @_;
	
	my $deltapx   = ( $o{zoomcanvas}->{height} / 2 ) - $y;
	my $yhop      = $o{zoomcanvas}->{dy} / $o{ipwin};
	my $deltaip   = int( $deltapx/$yhop );
	my $target    = $o{ipstart} - $deltaip;

	while( $o{ipstart} != $target ) {
		$deltaip = $o{ipstart} - $target;
		my $dir = $deltaip / abs( $deltaip );
		$o{ipstart} -= $dir*int( sqrt( abs( $o{ipstart} - $target ) ) );
		drawAlarms();
		$w{mw}->update();
		select( undef, undef, undef, 1/200 );		
	}
}

# this draws a given alarm on the main view
sub drawalarm {
	my ( $time, $alarm, $ip1, $ip2 ) = @_;
	my $color = alarm2color( $alarm );
	if ( my $ipoff = ip2off($ip1) ) {
		my $x = $o{maincanvas}->{margin_left} + 
			( $o{colwidth} * ( int( $o{num_cols} * $ipoff ) + percentOfDay($time) ) );
		my $y = $o{maincanvas}->{margin_top} + 
			( $o{colheight} * ( $o{num_cols} * $ipoff - int( $o{num_cols} * $ipoff ) ) );
		$w{c1}->createLine( $x, $y, $x+1, $y, -fill => $color, -tags => [ $color ] );
		$ips{$ip1} = [] unless defined $ips{$ip1};
		push( @{$ips{$ip1}}, [$time,$alarm,$ip1,$ip2] );
	}
	if ( my $ipoff = ip2off($ip2) ) {
		my $x = $o{maincanvas}->{margin_left} + 
			( $o{colwidth} * ( int( $o{num_cols} * $ipoff ) + percentOfDay($time) ) );
		my $y = $o{maincanvas}->{margin_top} + 
			( $o{colheight} * ( $o{num_cols} * $ipoff - int( $o{num_cols} * $ipoff ) ) );
		$w{c1}->createLine( $x, $y, $x+1, $y, -fill => $color, -tags => [ $color ] );
		$ips{$ip2} = [] unless defined $ips{$ip2};
		push( @{$ips{$ip2}}, [$time,$alarm,$ip1,$ip2] );
	}
}

# this draws a solid line across a column at a given ip
# this is useful for dividers
sub drawipline {
	my ( $ip ) = @_;
	my $ipoff = ip2off( ip2int( $ip ) ^ $xorhash );
	my $x = $o{maincanvas}->{margin_left} + 
		( $o{colwidth} * ( int( $o{num_cols} * $ipoff ) ) ) + 1;
	my $y = $o{maincanvas}->{margin_top} + 
		( $o{colheight} * ( $o{num_cols} * $ipoff - int( $o{num_cols} * $ipoff ) ) );
	$w{c1}->createLine( $x, $y, $x+$o{colwidth}-1, $y, -fill => 'grey50' );
}

# this calculates the percent of the day the time is.
# 0 = midnight, 0.5 = noon, 0.999 = 11:59
sub percentOfDay {
	my ( $time ) = @_;
	my ( $sec, $min, $hour ) = (localtime( $time ))[0..2];
	my $dayoffset = $sec+(($hour*60)+$min)*60;
	return( $dayoffset / (24*60*60) );
}

# this calculates the hour of the day the time is.
# 0 = midnight, 12 = noon, 23.999 = 11:59
sub timeToHourFraction {
	my ( $time ) = @_;
	my ( $sec, $min, $hour ) = (localtime( $time ))[0..2];
	my $dayoffset = $hour + ($min*(1/60)) + ($sec*(1/3600));
	return( $dayoffset );
}

# takes an dotted IP string and returns the 32-bit integer
sub ip2int { return unpack( "N", pack( "C4", split /\./, shift ) ); }
# takes a 32-bit integer and creates a dotted IP string
sub int2ip { return join( ".", unpack( "C4", pack( "N", shift ) ) ); }
# calculates the percent of the total IP space (of the given subnets) a 
# given ip is
# if you had only one subnet 128.61.0.0/16, then 128.61.128.0 would result in
# 0.5
sub ip2off {
	my ( $ip ) = shift;#ip2int( shift );
	my $offset = 0;
	my $total = 0; 
	for my $i ( 0..$#subnetint ) {
		my $sub = $subnetint[$i];
		my $mask = $subnetmask[$i];
		if ( ( $ip & $mask ) == $sub ) {
			$offset = $total + ( $ip & (~$mask) );
			return( $offset/$o{totalips} );
		}
		$total += (~$mask)+1;
	}
	return( 0 );
}
# this takes an offset (0 to 1) and returns the closest IP address from the
# given subnet ranges.
sub off2ip {
	my ( $offset ) = shift;
	return 0 if $offset > 1 or $offset < 0;
	my $total = 0; 
	for my $i ( 0..$#subnetint ) {
		my $sub = $subnetint[$i];
		my $mask = $subnetmask[$i];
		my $pretotal = $total;
		my $span = (~$mask)+1;
		$total += $span;
		if ( ( $total / $o{totalips} ) > $offset ) {
			my $suboff = ( $offset - $pretotal/$o{totalips} ) * ($o{totalips}/$span);
			return( int( $sub + ( $suboff  * $span ) ) );
		}
	}
	return( 0 );
}
# sums the sizes of each subnets together
sub countips {
	my ( @subnets ) = @_;
	my $total = 0;
	foreach my $subnet ( @subnets ) {
		my ( $sub, $mask ) = split( /\//, $subnet );
		push( @subnetint, ip2int( $sub ) ^ $xorhash );
		push( @subnetmask, ~((2<<(31-$mask))-1) );
		$total += (~$subnetmask[$#subnetmask])+1;
	}
	return( $total );
}
# convert alarm number to color
sub alarm2color {
	my ( $alarm ) = @_;
	my $color = ( $alarm > 77 )?'green':( $alarm > 66 )?'yellow':'red';
	return ( $color );
}
# toggle alarms to display
sub showalarms {
	my ( $mw, $alarmtype ) = @_;
	$o{current} = $alarmtype;
	$w{c1}->itemconfigure( 'red', -state => 'hidden' );
	$w{c1}->itemconfigure( 'green', -state => 'hidden' );
	$w{c1}->itemconfigure( 'yellow', -state => 'hidden' );
	$w{c1}->itemconfigure( $alarmtype, -state => 'normal' );
	return unless defined $w{tl};
	$w{c2}->itemconfigure( 'red', -state => 'hidden' );
	$w{c2}->itemconfigure( 'green', -state => 'hidden' );
	$w{c2}->itemconfigure( 'yellow', -state => 'hidden' );
	$w{c2}->itemconfigure( $alarmtype, -state => 'normal' );
}

sub pod2str {
	my ( $time ) = @_;
	my $hour = int( $time );
	my $min  = int( ($time - $hour) * 60 );
	return sprintf( "%02d:%02d", $hour, $min );
}
