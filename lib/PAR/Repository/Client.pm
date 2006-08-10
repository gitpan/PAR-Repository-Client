package PAR::Repository::Client;

use 5.006;
use strict;
use warnings;
use constant MODULES_DBM_FILE  => 'modules_dists.dbm';
use constant SYMLINKS_DBM_FILE => 'symlinks.dbm';
use constant REPOSITORY_INFO_FILE => 'repository_info.yml';

require PAR::Repository::Client::HTTP;
require PAR::Repository::Client::Local;

use Carp qw/croak/;
use File::Spec::Functions qw/splitpath/;
use PAR;
require version;
require Config;
require PAR::Dist;
require DBM::Deep;
require Archive::Zip;
require File::Temp;
require File::Copy;
require YAML::Tiny;

our $VERSION = '0.02';

# list compatible repository versions
our $Compatible_Versions = {
    $VERSION => 1,
};

=head1 NAME

PAR::Repository::Client - Access PAR repositories

=head1 SYNOPSIS

  use PAR::Repository::Client;
  
  my $client = PAR::Repository::Client->new(
    uri => 'http://foo/repository',
  );
  
  # This is happening at run-time, of course:
  # But calling import from your namespace
  $client->use_module('Foo::Bar') or die $client->error;
  
  $client->require_module('Bar::Baz') or die $client->error;

=head1 DESCRIPTION

This module represents the client for PAR repositories as
implemented by the L<PAR::Repository> module.

Chances are, you should be looking at the L<PAR> module
instead. Starting with version 0.950, it supports
automatically loading any modules that aren't found on your
system from a repository. If you need finer control than that,
then this module is the right one to use.

You can use this module to access repositories in one of
two ways: On your local filesystem or via HTTP. The
access methods are implemented in
L<PAR::Repository::Client::HTTP> and L<PAR::Repository::Client::Local>.
Any common code is in this module.

=head2 PAR REPOSITORIES

For a detailed discussion of the structure of PAR repositories, please
have a look at the L<PAR::Repository> distribution.

A PAR repository is, well, a repository of F<.par> distributions which
contain Perl modules and scripts. You can create F<.par> distributions
using the L<PAR::Dist> module or the L<PAR> module itself.

If you are unsure what PAR archives are, then have a look
at the L<SEE ALSO> section below, which points you at the
relevant locations.

=head1 METHODS

Following is a list of class and instance methods.
(Instance methods until otherwise mentioned.)

=cut

=head2 new

Creates a new PAR::Repository::Client object. Takes named arguments. 

Mandatory paramater:

I<uri> specifies the URI of the repository to use. Initially, http and
file URIs will be supported, so you can access a repository locally
using C<file:///path/to/repository> or just with C</path/to/repository>.
HTTP accessible repositories can be specified as C<http://foo> and
C<https://foo>.

Upon client creation, the repository's version is validated to be
compatible with this version of the client.

=cut

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    croak(__PACKAGE__."->new() takes an even number of arguments.")
      if @_ % 2;
    my %args = @_;
    
    croak(__PACKAGE__."->new() needs an 'uri' argument.")
      if not defined $args{uri};
    
    my $uri = $args{uri};

    my $obj_class = 'Local';
    if ($uri =~ /^https?:\/\//) {
        $obj_class = 'HTTP';
    }
    
    my $self = bless {
        uri => $uri,
        error => '',
        modules_dbm_temp_file => undef,
        modules_dbm_hash => undef,
        info => undef, # used for YAML info caching
    } => "PAR::Repository::Client::$obj_class";
    
    $self->_init(\%args);

    $self->validate_repository()
      or croak $self->{error};

    return $self;
}



=head2 require_module

First argument must be a package name (namespace) to require.
The method scans the repository for distributions that
contain the specified package.

When one or more distributions are found, it determines which
distribution to use using the C<prefered_distribution()> method.

Then, it fetches the prefered F<.par> distribution from the
repository and opens it using the L<PAR> module. Finally,
it loads the specified module from the downloaded
F<.par> distribution using C<require()>.

Returns 1 on success, the empty list on failure. In case
of failure, an error message can be obtained with the
C<error()> method.

=cut

sub require_module {
    my $self = shift;
    my $namespace = shift;
    $self->{error} = undef;

    # fetch the module, load preferably (fallback => 0)
    my $file = $self->get_module($namespace, 0);
    
    eval "require $namespace;";
    if ($@) {
        $self->{error} = "An error occurred while executing 'require $namespace;'. Error: $@";
        return();
    }
    
    return 1;
}


=head2 use_module

Works the same as the C<require_module> method except that
instead of only requiring the specified module, it also
calls the C<import> method if it exists. Any arguments to
this methods after the package to load are passed to the
C<import> call.

=cut

sub use_module {
    my $self = shift;
    my $namespace = shift;
    my @args = @_;
    $self->{error} = undef;

    my ($pkg) = caller();
    
    my $required = $self->require_module($namespace);
    return() if not $required; # error set by require_module

    eval "package $pkg; ${namespace}->import(\@args) if ${namespace}->can('import');";
    if ($@) {
        $self->{error} = "An error occurred while executing 'package $pkg; ${namespace}->import(\@args);'. Error: $@";
        return();
    }
    return 1;
}

=head2 get_module

First parameter must be a namespace, second parameter may be
a boolean indicating whether the PAR is a fallback-PAR or one
to load from preferably. (Defaults to false which means
loading preferably.)

Searches for a specified namespace in the repository and downloads
the corresponding PAR distribution. Automatically loads PAR
and appends the downloaded PAR distribution to the list of
PARs to load from.

Returns the name of the local
PAR file. Think of this as C<require_module> without actually
doing a C<require()> of the module.

=cut


sub get_module {
    my $self = shift;
    my $namespace = shift;
    my $fallback = shift;
    
    $self->{error} = undef;

    my ($modh) = $self->_modules_dbm;
    if (not defined $modh) {
        return();
    }

    my $dists = $modh->{$namespace};
    if (not defined $dists) {
        $self->{error} = "Could not find module '$namespace' in the repository.";
        return();
    }

    my $dist = $self->prefered_distribution($namespace, $dists);
    if (not defined $dist) {
        $self->{error} = "PAR: Could not find a distribution for package '$namespace'";
        return();
    }

    my $local_par_file = $self->fetch_par($dist);
    if (not defined $local_par_file or not -f $local_par_file) {
        return();
    }

    PAR->import( { file => $local_par_file, fallback => ($fallback?1:0) } );
    
    return $local_par_file;
}


=head2 error

Returns the last error message if there was an error or
the empty list otherwise.

=cut


sub error {
    my $self = shift;
    my $err = $self->{error};
    return(defined($err) ? $err : ());
}


=head2 prefered_distribution

Takes a namespace as first argument followed by a reference
to a hash of distribution file names with associated module
versions. The file name should have the following form:

  Math-Symbolic-0.502-x86_64-linux-gnu-thread-multi-5.8.7.par

This method decides which distribution to load and returns
that file name.

=cut

sub prefered_distribution {
    my $self = shift;
    $self->{error} = undef;
    my $ns = shift;
    my $dists = shift;

    return() if not keys %$dists;
    
    my $this_pver = $Config::Config{version};
    my $this_arch = $Config::Config{archname};

    my @sorted;
    foreach my $dist (keys %$dists) {
        # distfile, version, distname, distver, arch, pver
        my $ver = version->new($dists->{$dist}||0);
        my ($n, $v, $a, $p) = PAR::Dist::parse_dist_name($dist);
        next if not defined $a or not defined $p;
        # skip the ones for other archs
        next if $a ne $this_arch and $a ne 'any_arch';
        next if $p ne $this_pver and $a ne 'any_version';
        
        # as a fallback while sorting, prefer arch and pver
        # specific dists to fallbacks
        my $order_num =
            ($a eq 'any_arch' ? 2 : 0)
            + ($p eq 'any_version' ? 1 : 0);
        push @sorted, [$dist, $ver, $order_num];
    }
    return() if not @sorted;
    
    # sort by version, highest first.
    @sorted =
        sort {
            # sort version
            $b->[1] <=> $a->[1]
                or
            # specific before any_version before any_arch before any_*
            $a->[2] <=> $b->[2]
        }
        @sorted;

    
    my $dist = shift @sorted;
    return $dist->[0];
}

=head2 validate_repository_version

Accesses the repository meta information and validates that it
has a compatible version. This is done on object creation, so
it should not normally be necessary to call this from user code.

Returns a boolean indicating the outcome of the operation.

=cut

sub validate_repository_version {
    my $self = shift;
    $self->{error} = undef;

    my $info = $self->_repository_info;
    if (not defined $info) {
        return();
    }
    elsif (not exists $info->{repository_version}) {
        $self->{error} = "Repository info file ('repository_info.yml') does not contain a version.";
        return();
    }
    elsif (
        not exists
        $PAR::Repository::Client::Compatible_Versions->{
            $info->{repository_version}
        }
    ) {
        $self->{error} = "Repository has an incompatible version (".$info->{repository_version}.")";
        return();
    }
    return 1;
}

=head2 _modules_dbm

This is a private method.

Fetches the C<modules_dists.dbm> database from the repository,
ties it to a L<DBM::Deep> object and returns a tied hash
reference or the empty list on failure. Second return
value is the name of the local temporary file.

In case of failure, an error message is available via
the C<error()> method.

The method uses the C<_fetch_dbm_file()> method which must be
implemented in a subclass such as L<PAR::Repository::Client::HTTP>.

=cut

sub _modules_dbm {
    my $self = shift;
    $self->{error} = undef;
    
    $self->_close_modules_dbm;
    
    my $file = $self->_fetch_dbm_file(MODULES_DBM_FILE().".zip");
    # (error set by _fetch_dbm_file)
    return() if not defined $file; # or not -f $file; # <--- _fetch_dbm_file should do the stat!
    
    my ($tempfh, $tempfile) = File::Temp::tempfile(
		'temporary_dbm_XXXXX',
		UNLINK => 0,
		DIR => File::Spec->tmpdir(),
	);
    
	if (not $self->_unzip_file($file, $tempfile, MODULES_DBM_FILE())) {
        $self->{error} = "Could not unzip dbm file '$file' to '$tempfile'";
        return();
    }

    unlink $file;
    
    $self->{modules_dbm_temp_file} = $tempfile;

	my %hash;
    my $obj = tie %hash, "DBM::Deep", {
		file => $tempfile,
		locking => 1,
	}; 

    $self->{modules_dbm_hash} = \%hash;
	return (\%hash, $tempfile);
}


=head2 _close_modules_dbm

This is a private method.

Closes the C<modules_dists.dbm> file and does all necessary
cleaning up.

This is called when the object is destroyed.

=cut

sub _close_modules_dbm {
	my $self = shift;
	my $hash = $self->{modules_dbm_hash};
	return if not defined $hash;

	my $obj = tied($hash);
	$self->{modules_dbm_hash} = undef;
	undef $hash;
	undef $obj;
	
	unlink $self->{modules_dbm_temp_file};
	$self->{modules_dbm_temp_file} = undef;

	return 1;
}


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

sub DESTROY {
    my $self = shift;
    $self->_close_modules_dbm;
}

1;
__END__

=head1 SEE ALSO

This module is directly related to the C<PAR> project. You need to have
basic familiarity with it. Its homepage is at L<http://par.perl.org/>

See L<PAR>, L<PAR::Dist>, L<PAR::Repository>, etc.

L<PAR::Repository> implements the server side creation and manipulation
of PAR repositories.

L<PAR::WebStart> is doing something similar but is otherwise unrelated.

=head1 AUTHOR

Steffen Müller, E<lt>smueller@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2006 by Steffen Müller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.6 or,
at your option, any later version of Perl 5 you may have available.

=cut