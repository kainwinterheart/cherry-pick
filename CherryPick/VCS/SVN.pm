package CherryPick::VCS::SVN;

use strict;
use warnings;

use Mouse;

use SVN::Client ();

use String::ShellQuote 'shell_quote';

use File::Temp 'tmpnam';

use boolean;

use namespace::autoclean;

extends 'CherryPick::VCS';

has 'backend' => ( is => 'ro', isa => 'SVN::Client', init_arg => undef, lazy => true, builder => 'build_backend' );

after [ 'can_update', 'update', 'merge', 'diff', 'revert', 'propset' ] => sub {

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

    @revisions = sort{ $a <=> $b } @revisions;

    return \@revisions;
}

sub precheck {

    my ( $self, $file ) = @_;

    unless( $self -> can_update( $file ) ) {

        die( sprintf( 'File %s is dirty', $file ) );
    }

    return;
}

sub prepare {

    my ( $self, $file, $revisions ) = @_;

    $self -> update( $file, $revisions -> [ 0 ] - 1 );

    foreach my $rev ( @$revisions ) {

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

    $self -> backend() -> update( $file, $rev, true );

    return;
}

sub merge {

    my ( $self, $file, $rev ) = @_;

    $self -> backend() -> merge( $file, $rev - 1, $file, $rev, $file, true, false, false, false );
    # system( sprintf( 'svn merge -c %d %s', $rev, shell_quote( $file ) ) );

    return;
}

sub diff {

    my ( $self, $file ) = @_;

    $file = $self -> to_rel( $file );

    my ( $fh, $diff_file ) = tmpnam();

    $self -> backend() -> diff( [], $file, 'BASE', $file, 'WORKING', true, false, false, $fh, *STDERR );

    seek( $fh, 0, 0 );

    my $out = join( '', <$fh> );

    close( $fh );
    unlink( $diff_file );

    return $out;
}

sub revert {

    my ( $self, $file ) = @_;

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

