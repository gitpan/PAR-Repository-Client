package PAR::Repository::Client::HTTP;

use 5.006;
use strict;
use warnings;

require LWP::Simple;

use base 'PAR::Repository::Client';

use Carp qw/croak/;

our $VERSION = '0.01';

=head1 NAME

PAR::Repository::Client::HTTP - PAR repository via HTTP

=head1 SYNOPSIS

  use PAR::Repository::Client;
  
  my $client = PAR::Repository::Client->new(
    uri => 'http:///foo/repository',
  );

=head1 DESCRIPTION

This module implements repository accesses via HTTP.

If you create a new L<PAR::Repository::Client> object and pass it
an uri parameter which starts with C<http://> or C<https://>,
it will create an object of this class. It inherits from
C<PAR::Repository::Client>.

The repository is accessed using L<LWP::Simple>.

=head2 EXPORT

None.

=head1 METHODS

Following is a list of class and instance methods.
(Instance methods until otherwise mentioned.)

=cut


=head2 fetch_par

Fetches a .par distribution from the repository and stores it
locally. Returns the name of the local file or the empty list on
failure.

First argument must be the distribution name to fetch.

=cut

sub fetch_par {
    my $self = shift;
    $self->{error} = undef;
    my $dist = shift;
    return() if not defined $dist;
    
    my $url = $self->{uri};
    $url =~ s/\/$//;
    
    my ($n, $v, $a, $p) = PAR::Dist::parse_dist_name($dist);
    $url .= "/$a/$p/$n-$v-$a-$p.par";
    
    my $file = $self->_fetch_file($url);

    if (not defined $file) {
        $self->{error} = "Could not fetch distribution from URI '$url'";
        return();
    }

    return $file;
}


{
    my %escapes;
    sub _fetch_file {
        my $self = shift;
        $self->{error} = undef;
        my $file = shift;
        
        $ENV{PAR_TEMP} ||= File::Spec->catdir(File::Spec->tmpdir, 'par');
        mkdir $ENV{PAR_TEMP}, 0777;
        %escapes = map { chr($_) => sprintf("%%%02X", $_) } 0..255 unless %escapes;
        
        my $local_file = $file;
        $local_file =~ s/([^\w\.])/$escapes{$1}/g;
        $local_file = File::Spec->catfile( $ENV{PAR_TEMP}, $local_file);

        my $rc = LWP::Simple::mirror( $file, $local_file );
        if (!LWP::Simple::is_success($rc) and not $rc == HTTP::Status::RC_NOT_MODIFIED()) {
            $self->{error} = "Error $rc: " . LWP::Simple::status_message($rc) . " ($file)\n";
            return();
        }
        
        return $local_file if -f $local_file;
        return;
    }
}


=head2 validate_repository

Makes sure the repository is valid. Returns the empty list
if that is not so and a true value if the repository is valid.

The error message is available as C<$client->error()> on
failure.

=cut

sub validate_repository {
    my $self = shift;
    $self->{error} = undef;

    my $mod_db = $self->_modules_dbm;
    return 1 if defined $mod_db;
    return();
}


=head2 _fetch_dbm_file

This is a private method.

Fetches a dbm (index) file from the repository and
returns the name of the temporary local file or the
empty list on failure.

An error message is available via the C<error()>
method in case of failure.

=cut

sub _fetch_dbm_file {
    my $self = shift;
    $self->{error} = undef;
    my $file = shift;
    return if not defined $file;

    my $url = $self->{uri};
    $url =~ s/\/$//;

    my $local = $self->_fetch_file("$url/$file");
    return() if not defined $local or not -f $local;
    
    return $local;
}



=head2 _init

This private method is called by the C<new()> method of
L<PAR::Repository::Client>. It is used to initialize
the client object and C<new()> passes it a hash ref to
its arguments.

=cut

sub _init {
    # We implement additional object attributes here
    # Currently no extra attributes...
}



1;
__END__

=head1 SEE ALSO

This module is part of the L<PAR::Repository::Client> distribution.

This module is directly related to the C<PAR> project. You need to have
basic familiarity with it. The PAR homepage is at L<http://par.perl.org>.

See L<PAR>, L<PAR::Dist>, L<PAR::Repository>, etc.

L<PAR::Repository> implements the server side creation and manipulation
of PAR repositories.

L<PAR::WebStart> is doing something similar but is otherwise unrelated.

The repository access is done via L<LWP::Simple>.

=head1 AUTHOR

Steffen Müller, E<lt>smueller@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2006 by Steffen Müller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.6 or,
at your option, any later version of Perl 5 you may have available.

=cut
