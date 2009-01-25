package PAR::Repository::Client::Util;

use 5.006;
use strict;
use warnings;

our $VERSION = '0.21';

use Carp qw/croak/;

=head1 NAME

PAR::Repository::Client::Util - Small helper methods common to all implementations

=head1 SYNOPSIS

  use PAR::Repository::Client;

=head1 DESCRIPTION

This module implements small helper methods which are common to all
L<PAR::Repository::Client> implementations.

=head1 PRIVATE METHODS

These private methods should not be relied upon from the outside of
the module.

=head2 _unzip_file

This is a private method. Callable as class or instance method.

Unzips the file given as first argument to the file
given as second argument.
If a third argument is used, the zip member of that name
is extracted. If the zip member name is omitted, it is
set to the target file name.

Returns the name of the unzipped file.

=cut

sub _unzip_file {
  my $class = shift;
  my $file = shift;
  my $target = shift;
  my $member = shift;
  $member = $target if not defined $member;
  return unless -f $file;

  my $zip = Archive::Zip->new;
  local %SIG;
  $SIG{__WARN__} = sub { print STDERR $_[0] unless $_[0] =~ /\bstat\b/ };

  return unless $zip->read($file) == Archive::Zip::AZ_OK()
    and $zip->extractMember($member, $target) == Archive::Zip::AZ_OK();

  return $target;
}


=head2 _parse_dbm_checksums

This is a private method.

Given a reference to a file handle, a reference to a string
or a file name, this method parses a checksum file
and returns a hash reference associating file names
with their base64 encoded MD5 hashes.

If passed a ref to a string, the contents of the string will
be assumed to contain the checksum data.

=cut

sub _parse_dbm_checksums {
  my $self = shift;
  $self->{error} = undef;

  my $file_or_fh = shift;
  my $is_string = 0;
  my $fh;
  if (ref($file_or_fh) eq 'GLOB') {
    $fh = $file_or_fh;
  }
  elsif (ref($file_or_fh) eq 'SCALAR') {
    $is_string = 1;
  }
  else {
    open $fh, '<', $file_or_fh
      or die "Could not open file '$file_or_fh' for reading: $!";
  }

  my $hashes = {};
  my @lines;
  @lines = split /\n/, $$file_or_fh if $is_string;

  while (1) {
    local $_ = $is_string ? shift @lines : <$fh>;
    last if not defined $_;
    next if /^\s*$/ or /^\s*#/;
    my ($file, $hash) = split /\t/, $_;
    if (not defined $file or not defined $hash) {
      $self->{error} = "Error reading repository checksums.";
      return();
    }
    $hash =~ s/\s+$//;
    $hashes->{$file} = $hash;
  }

  return $hashes;
}



sub DESTROY {
  my $self = shift;
  $self->close_modules_dbm;
  $self->close_scripts_dbm;
}

1;
__END__

=head1 SEE ALSO

This module is directly related to the C<PAR> project. You need to have
basic familiarity with it. Its homepage is at L<http://par.perl.org/>

See L<PAR>, L<PAR::Dist>, L<PAR::Repository>, etc.

L<PAR::Repository::Query> implements the querying interface. The methods
described in that module's documentation can be called on
C<PAR::Repository::Client> objects.

L<PAR::Repository> implements the server side creation and manipulation
of PAR repositories.

L<PAR::WebStart> is doing something similar but is otherwise unrelated.

=head1 AUTHOR

Steffen Mueller, E<lt>smueller@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2006-2009 by Steffen Mueller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.6 or,
at your option, any later version of Perl 5 you may have available.

=cut
