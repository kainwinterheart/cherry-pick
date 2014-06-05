package CherryPick::VCS;

use strict;
use warnings;

use Mouse;

use Cwd 'getcwd';

use File::Spec ();

use boolean;

use namespace::autoclean;


has 'wcpath' => ( is => 'ro', isa => 'Str', init_arg => undef, lazy => true, builder => 'build_wcpath' );


sub build_wcpath {

    my ( $self ) = @_;

    return getcwd();
}

sub to_abs {

    my ( $self, $file ) = @_;

    $file = File::Spec -> rel2abs( $file, $self -> wcpath() );
    $file = File::Spec -> canonpath( $file );

    return $file;
}

sub to_rel {

    my ( $self, $file ) = @_;

    $file = File::Spec -> abs2rel( $file, $self -> wcpath() );
    $file = File::Spec -> canonpath( $file );

    return $file;
}

=head2 parse_revspec( Str $revspec )

=cut

sub parse_revspec;

=head2 get_changes( Str $file )

=cut

sub get_changes;

=head2 precheck( Str $file )

=cut

sub precheck;

=head2 prepare( Str $file, ArrayRef[Int] $revisions )

=cut

sub prepare;

=head2 clean( Str $file )

=cut

sub clean;

__PACKAGE__ -> meta() -> make_immutable();

1;

__END__

