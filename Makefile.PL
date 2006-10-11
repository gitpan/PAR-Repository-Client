use 5.006;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

WriteMakefile(
    NAME              => 'PAR::Repository::Client',
    VERSION_FROM      => 'lib/PAR/Repository/Client.pm', # finds $VERSION
    PREREQ_PM         => {
#'perl'      => '5.6',
        'DBM::Deep' => '0',
        'version' => '0.50',
        'File::Spec' => '0',
        'PAR::Dist' => '0.20',
        'PAR' => '0.950',
        'LWP::Simple' => '0',
        'Archive::Zip' => '0',
        'YAML::Tiny' => '0',
        'PAR::Repository::Query' => '0.12',
    }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/PAR/Repository/Client.pm', # retrieve abstract from module
       AUTHOR         => 'Steffen Müller <smueller@cpan.org>') : ()),
);
