package MifosX::DataImporter::UserAgent;

use base 'LWP::UserAgent';

my %config;

sub new {
  my $class = shift;
  my %opts = @_;
  $config{$_} = $opts{$_} foreach qw(username password);
  my $self = bless $class->SUPER::new(@_), $class;
}

sub get_basic_credentials {
  return $config{username}, $config{password};
}

1;
