#!/usr/bin/perl

use strict;
use warnings;

package cherry_pick_bin;

use Getopt::Long 'GetOptions';

use CherryPick ();

use Carp 'confess';

$SIG{ __DIE__ } = \&confess;

my ( $cfg ) = @ARGV;

exit 1 unless $cfg;

chomp( $cfg );

my $o = CherryPick -> new( config => $cfg );

my $list = $o -> process();

foreach my $node ( @$list ) {

    print $node -> { 'diff' }, "\n";
}

exit 0;

