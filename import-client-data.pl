#!/usr/bin/perl

use strict;
use warnings;

use lib 'lib';
use MifosX::DataImporter::ClientImporter;
use Getopt::Long;

my $confpath = 'mifosx.conf';
my $gensample = 0;
GetOptions(
    "config=s" => \$confpath,
    "gensample" => \$gensample
);

my $ci = MifosX::DataImporter::ClientImporter->new(
    config => $confpath
);

my $csvpath = pop @ARGV || 'sample-client.csv';
if ($gensample) {
    $ci->gen_sample_csv($csvpath);
    print "Generated sample file $csvpath\n";
} else {
    $ci->import_csv($csvpath);
}

