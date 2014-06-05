package CherryPick::VCS::SVN;

use strict;
use warnings;

use Mouse;

use SVN::Client ();

use File::Temp 'tmpnam';

use List::Util 'min';
use List::MoreUtils 'uniq';

use String::ShellQuote 'shell_quote';

use boolean;

use namespace::autoclean;

extends 'CherryPick::VCS';

has 'backend' => ( is => 'ro', isa => 'SVN::Client', init_arg => undef, lazy => true, builder => 'build_backend' );

after [ 'can_update', 'update', 'merge', 'diff', 'revert', 'propset', 'get_base_rev', 'add' ] => sub {

    my ( $self ) = @_;

    $self -> backend() -> pool() -> clear();
};


sub build_backend {

    my ( $self ) = @_;

    return SVN::Client -> new();
}

sub parse_revspec {

    my ( $self, $revspec ) = @_;

    my @revisions = ();

    foreach my $part ( split( /,\s*/, $revspec ) ) {

        if( $part =~ m/^[0-9]+$/ ) {

            push( @revisions, int( $part ) );

        } elsif( $part =~ m/^([0-9]+)-([0-9]+)$/ ) {

            push( @revisions, int( $1 ) .. int( $2 ) );

        } else {

            die( sprintf( 'Invalid revision: %s', $part ) );
        }
    }

    @revisions = uniq( sort( { $a <=> $b } @revisions ) );

    return \@revisions;
}

sub least_revision {

    my ( $self, $revisions ) = @_;

    return min( @$revisions );
}

sub precheck {

    my ( $self, $file ) = @_;

    unless( $self -> can_update( $file ) ) {

        die( sprintf( 'File %s is dirty', $file ) );
    }

    return;
}

sub init {

    my ( $self, $file, $revision ) = @_;

    $self -> update( $file, $revision - 1 );

    return;
}

sub prepare {

    my ( $self, $file, $revisions ) = @_;

    my @collapsed_revs  = ();
    my $total_revisions = scalar( @$revisions );

    for( my $i = 0; $i < $total_revisions; ++$i ) {

        my $from = $revisions -> [ $i ];
        my $to   = $from;

        while( defined $revisions -> [ $i + 1 ] ) {

            my $l_to = $revisions -> [ $i + 1 ];

            if( $l_to == ( $to + 1 ) ) {

                $to = $l_to;

                ++$i;

            } else {

                last;
            }
        }

        push( @collapsed_revs, [ $from, $to ] );
    }

    foreach my $rev ( @collapsed_revs ) {

        $self -> merge( $file, $rev );
    }

    $self -> propdel( $file, 'svn:mergeinfo' );

    return;
}

sub get_changes {

    my ( $self, $file ) = @_;

    return $self -> diff( $file );
}

sub clean {

    my ( $self, $file ) = @_;

    $self -> revert( $file );
    $self -> update( $file, 'HEAD' );

    return;
}

sub update {

    my ( $self, $file, $rev ) = @_;

    $self -> trace( 'svn up -r', $rev, $file );

    $self -> backend() -> update( $file, $rev, true );

    return;
}

sub merge {

    my ( $self, $file, $rev ) = @_;

    my $from = $rev -> [ 0 ] - 1;
    my $to   = $rev -> [ 1 ];

    # $self -> trace( 'svn merge -r', "$from:$to", $file );
    #
    # $self -> backend() -> merge( $file, $from, $file, $to, $file, true, false, false, false );

    my $diff = $self -> _diff( $file, $from, $to );

    $self -> patch( $diff );

    return;
}

sub add {

    my ( $self, $file ) = @_;

    $self -> trace( 'svn add', $file );

    $self -> backend() -> add( $file, true );

    return;
}

sub patch {

    my ( $self, $diff ) = @_;

    my ( $fh, $diff_file ) = tmpnam();

    print $fh $diff;

    close( $fh );

    my $cmd = sprintf( 'patch -s -p0 < %s', shell_quote( $diff_file ) );

    $self -> trace( $cmd );

    my $code = system( $cmd );

    unlink( $diff_file );

    if( $code >> 8 ) {

        die sprintf( 'Patch failed with code %d', $code );
    }

    return;
}

sub diff {

    my ( $self, $file ) = @_;

    my $from = $self -> get_base_rev( $file );
    my $to   = 'WORKING';

    return $self -> _diff( $file, $from, $to );
}

sub _diff {

    my ( $self, $file, $from, $to ) = @_;

    $file = $self -> to_rel( $file );

    my ( $fh, $diff_file ) = tmpnam();

    $self -> trace( 'svn diff -r', "$from:$to", $file );

    $self -> backend() -> diff( [], $file, $from, $file, $to, true, false, false, $fh, *STDERR );

    seek( $fh, 0, 0 );

    my $out = join( '', <$fh> );

    close( $fh );
    unlink( $diff_file );

    return $out;
}

sub get_base_rev {

    my ( $self, $file ) = @_;

    my $base_rev  = 'BASE';
    my $info_func = sub {

        $base_rev = $_[ 1 ] -> rev();
    };

    $self -> backend() -> info( $file, undef, undef, $info_func, false );

    return $base_rev;
}

sub revert {

    my ( $self, $file ) = @_;

    $self -> trace( 'svn revert', $file );

    $self -> backend() -> revert( $file, true );

    return;
}

sub propdel {

    my ( $self, $file, $prop ) = @_;

    return $self -> propset( $file, $prop, undef );
}

sub propset {

    my ( $self, $file, $prop, $val ) = @_;

    $self -> backend() -> propset( $prop, $val, $file, true );

    return;
}

sub can_update {

    my ( $self, $file ) = @_;

    my @entries = ();
    my $stat_func = sub {
        # ignore entries with statuses: none|normal|ignored;)|external
        unless( ( $_[ 1 ] -> text_status() =~ m/^(2|3|11|13)$/ ) && ( $_[ 1 ] -> repos_text_status() eq $SVN::Wc::Status::none ) ) {
            push( @entries, \@_ );
        }
    };

    $self -> backend() -> status( $file, undef, $stat_func, true, true, true, true );

    if( scalar( grep( { $_ -> [ 1 ] -> text_status() =~ m/^(8|10)$/ } @entries ) ) ) {

        return false;

    } else {

        return true;
    }
}

__PACKAGE__ -> meta() -> make_immutable();

1;

__END__
