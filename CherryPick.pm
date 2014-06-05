package CherryPick;

use strict;
use warnings;

use Mouse;

use YAML ();

use File::Spec ();
use File::Slurp 'slurp';

use Module::Load 'load';

use namespace::autoclean;

use boolean;


has '_config' => ( is => 'ro', isa => 'Str', required => true, init_arg => 'config' );

has 'config' => ( is => 'ro', isa => 'HashRef', init_arg => undef, lazy => true, builder => 'load_config' );

has 'vcs' => ( is => 'ro', isa => 'CherryPick::VCS', init_arg => undef, lazy => true, builder => 'load_vcs' );


sub cget {

    my ( $self, $key ) = @_;

    return $self -> config() -> { $key };
}

sub load_vcs {

    my ( $self ) = @_;

    my $base = sprintf( '%s::VCS', ref( $self ) );
    my $vcs  = sprintf( '%s::%s', $base, $self -> cget( 'vcs' ) );

    if( eval{ load( $vcs ); 1 } ) {

        if( $vcs -> isa( $base ) ) {

            return $vcs -> new();
        }

    } else {

        warn $@;
    }

    die sprintf( 'Unknown VCS plugin: %s', $vcs );
}

sub load_config {

    my ( $self ) = @_;

    return YAML::Load( scalar( slurp( $self -> _config() ) ) );
}

sub process {

    my ( $self ) = @_;

    my $list = $self -> cget( 'files' );
    my $vcs  = $self -> vcs();
    my @out  = ();

    my @nodes = ();
    my %files = ();

    foreach my $node ( @$list ) {

        my $revisions = $vcs -> parse_revspec( $node -> { 'rev' } );

        my $files = $node -> { 'file' };

        unless( ref( $files ) eq 'ARRAY' ) {

            $files = [ $files ];
        }

        foreach my $file ( @$files ) {

            $file = $vcs -> to_abs( $file );

            push( @nodes, [ $file, $revisions ] );
            push( @{ $files{ $file } }, @$revisions );
        }
    }

    my @sorted_files = sort( keys( %files ) );
    my $sorted_files = scalar( @sorted_files );

    for( my $i = 0; $i < $sorted_files; ++$i ) {

        my $root = $sorted_files[ $i ];

        next unless( -d $root );

        my @root = File::Spec -> splitdir( $root );
        my $root_parts = scalar( @root );

SCAN_FOR_SUBDIRS:
        while( defined $sorted_files[ $i + 1 ] ) {

            my $subpath = $sorted_files[ $i + 1 ];

            my @subpath = File::Spec -> splitdir( $subpath );

            if( $root_parts >= scalar( @subpath ) ) {

                last;
            }

            for( my $j = 0; $j < $root_parts; ++$j ) {

                if( $root[ $j ] ne $subpath[ $j ] ) {

                    last SCAN_FOR_SUBDIRS;
                }
            }

            push( @{ $files{ $root } }, @{ delete( $files{ $subpath } ) } );

            ++$i;
        }
    }

    $self -> stage( 'precheck' );

    while( my ( $file, $dummy ) = each( %files ) ) {

        $vcs -> precheck( $file );
    }

    $self -> stage( 'init' );

    while( my ( $file, $revisions ) = each( %files ) ) {

        $self -> trace( "\t", $file );

        my $revision = $vcs -> least_revision( $revisions );

        $vcs -> init( $file, $revision );
    }

    $self -> stage( 'prepare' );

    foreach my $node ( @nodes ) {

        $self -> trace( "\t", $node -> [ 0 ] );

        $vcs -> prepare( @$node[ 0, 1 ] );
    }

    $self -> stage( 'processing' );

    while( my ( $file, $dummy ) = each( %files ) ) {

        $self -> trace( "\t", $file );

        push( @out, $self -> process_file( $file, $vcs ) );
    }

    $self -> stage( 'cleanup' );

    while( my ( $file, $dummy ) = each( %files ) ) {

        $vcs -> clean( $file );
    }

    return \@out;
}

sub stage {

    my ( $self, $name ) = @_;

    $self -> trace( 'STAGE:', $name );

    return;
}

sub trace {

    my ( $self, @arr ) = @_;

    print STDERR join( ' ', @arr ), "\n";

    return;
}

sub process_file {

    my ( $self, $file, $vcs ) = @_;

    $vcs //= $self -> vcs();

    my $diff = $vcs -> get_changes( $file );

    return {
        file => $vcs -> to_rel( $file ),
        diff => $diff,
    };
}


__PACKAGE__ -> meta() -> make_immutable();

1;

__END__
