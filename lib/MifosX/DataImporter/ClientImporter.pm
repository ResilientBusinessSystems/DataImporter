package MifosX::DataImporter::ClientImporter;

use Config::General 'ParseConfig';
use Text::CSV_XS;
use Data::Dumper;
use JSON;
use MifosX::DataImporter::UserAgent;

my $json = JSON->new;

sub _get_conf {
    my ($conf, $parm) = @_;
    return $conf->{$parm} || $conf->{"mifos.$parm"};
}

sub _get_data {
    my ( $self, $path, $callback ) = @_;
    my $ua = $self->{ua};
    my $API_URL = $self->{endpoint};
    my $url = "$API_URL/$path";
    my $resp = $ua->get($url);
    if ($resp->code =~ m/^20[01]/) {
        my $data = $json->decode($resp->content);
        die "Didn't return list for $path" unless 'ARRAY' eq ref($data);
        &$callback($_) foreach @$data;
    } else {
        die "Failed to read $path data at $API_URL\n" .
            "Response: " . $resp->content . "\n";
    }
}

sub new {
    my $class = shift;
    my %args = @_;
    my $confpath = $args{config} || 'mifosx.conf';
    my $config = { ParseConfig($confpath) };
    my $self = {
        map { $_ => _get_conf($config, $_) } qw(user.id password)
    };
    my $tenantId = _get_conf($config, 'tenant.id');
    my $endpoint = _get_conf($config, 'endpoint');
    unless ($endpoint) {
        my $baseUrl = _get_conf($config, 'baseurl');
        $endpoint = "$baseUrl/mifosng-provider/api/v1";
    }
    $self->{endpoint} = $endpoint;
    my ( $username, $password ) = map { _get_conf($config, $_) } qw(user.id password);

    my $headers = HTTP::Headers->new;
    $headers->header('Content-Type' => 'application/json');
    $headers->header('X-Mifos-Platform-TenantId' => $tenantId);
    $self->{ua} = MifosX::DataImporter::UserAgent->new(
        default_headers => $headers,
        username    => $username,
        password    => $password
    );

    my $officeHash = {};
    my $staffHash = {};
    my $codeHash = {};
    my $cvHash = {};
    my $dtColList = {};
    my $dtColCode = {};

    _get_data($self, "offices", sub {
        $officeHash->{$_->{name}} = $_->{id};
    } );

    _get_data($self, "staff", sub {
        $staffHash->{$_->{displayName}} = $_->{id};
    } );

    _get_data($self, "codes", sub {
        $codeHash->{$_->{name}} = $_->{id};
    } );

    _get_data($self, "datatables", sub {
        if ($_->{applicationTableName} eq "m_client") {
            my $cHash = {};
            my $cList = [];
            my $dtName = $_->{registeredTableName};
            my $colHdrs = $_->{columnHeaderData};
            foreach my $col (@$colHdrs) {
                next if $col->{isColumnPrimaryKey};
                my $cn = $col->{columnName};
                if ($col->{columnDisplayType} eq 'CODELOOKUP') {
                    my $codeNm = $col->{columnCode};
                    $cn =~ s/^${codeNm}_cd_//;
                    $cHash->{$cn} = $codeNm;
                    print "Empty code for $cn" unless length($codeNm);
                    my $cVals = {};
                    my $cvs = $col->{columnValues};
                    foreach my $cv (@$cvs) {
                        $cVals->{$cv->{value}} = $cv->{id};
                    }
                    $cvHash->{$codeNm} = $cVals;
                }
                push(@$cList, $cn);
            }
            $dtColCode->{$dtName} = $cHash;
            $dtColList->{$dtName} = $cList;
        }
    } );

    foreach my $cn ("Gender") {
        my $cid = $codeHash->{$cn};
        $cvHash->{$cn} = {};
        _get_data($self, "codes/$cid/codevalues", sub {
            $cvHash->{$cn}->{$_[0]->{name}} = $_[0]->{id}
        } )
    }

    $self->{officeHash} = $officeHash;
    $self->{staffHash} = $staffHash;
    $self->{codeHash} = $codeHash;
    $self->{cvHash} = $cvHash;
    $self->{dtColList} = $dtColList;
    $self->{dtColCode} = $dtColCode;

    $self->{csv} = Text::CSV_XS->new( { binary => 1 } )
        or die "Cannot use CSV: " . Text::CSV_XS->error_diag();

    return bless $self, $class;
}

sub _get_code_value { return $_[0]->{cvHash}->{$_[1]}->{$_[2]} }

my @colList = (
    "Full/Business Name*",
    "Office Name*",
    "Staff Name*",
    "External ID",
    "Activation Date*",
    "Active*",
    "Submitted Date",
    "Mobile No",
    "Date of Birth",
    "Gender"
);

my %colKeys = (
    "Full/Business Name*" => "fullname",
    "Office Name*" => "officeId",
    "Staff Name*" => "staffId",
    "External ID" => "externalId",
    "Activation Date*" => "activationDate",
    "Active*" => "active",
    "Submitted Date" => "submittedOnDate",
    "Mobile No" => "mobileNo",
    "Gender" => "genderId",
    "Date of Birth" => "dateOfBirth"
);

my %colSub = (
    officeId => sub { return $_[0]->{officeHash}->{$_[1]} },
    staffId => sub { return $_[0]->{staffHash}->{$_[1]} },
    genderId => sub { return &_get_code_value($_[0], "Gender", $_[1]) }
);

sub gen_sample_csv {
    my ( $self, $csvfile ) = @_;

    return if (-e $csvfile);

    my $header_row = [@colList];
    my $table_row = [];
    push(@$table_row, '') foreach @colList;

    $dtColList = $self->{dtColList};

    while (my ($dtName, $colList) = each(%$dtColList)) {
        my $first = 1;
        foreach my $col (@$colList) {
            push(@$header_row, $col);
            if ($first) {
                push(@$table_row, $dtName);
                $first = 0;
            } else {
                push(@$table_row, '');
            }
        }
    }

    my $csv = $self->{csv};
    $csv->eol("\r\n");
    open(my $fh, ">", $csvfile);
    $csv->print($fh, $_) foreach ($table_row, $header_row);
    close($fh);
}

sub _do_post {
    my ( $self, $url, $hash, $respCallback ) = @_;

    my $ua = $self->{ua};
    my $req = HTTP::Request->new('POST', $url);
    my $content = $json->encode($hash);
    $req->content($content);
    my $resp = $ua->request($req);
    &$respCallback($content, $resp);
}

sub import_csv {
    my ( $self, $csvfile ) = @_;

    $staffHash = $self->{staffHash};
    $codeHash = $self->{codeHash};
    $cvHash = $self->{cvHash};
    $dtColList = $self->{dtColList};
    $dtColCode = $self->{dtColCode};

    my $table_ranges = [ {
        name => "m_client",
        from => 0
    } ];

    open(my $fh, "<:encoding(utf8)", $csvfile) or die "Failed to open $csvfile";

    my $csv = $self->{csv};
    if (my $table_row = $csv->getline($fh)) {
        my $n = scalar @$table_row;
        foreach my $i (0..$n-1) {
            my $col = $table_row->[$i];
            if (length($col)) {
                my $m = scalar @$table_ranges;
                push(@$table_ranges, {
                    name => $col,
                    from => $i
                } );
                $table_ranges->[$m-1]->{to} = $i-1;
            }
        }
    }

    my $dti = 0;
    my $table_headers = {};
    my $header;
    if ($header = $csv->getline($fh)) {
        my $m = $#$table_ranges;
        my $n = $#$header;
        $table_ranges->[$m]->{to} = $n;
    }

    foreach my $dt (@$table_ranges) {
        printf "Got data table: '%s' range %d to %s\n", $dt->{name}, $dt->{from}, $dt->{to}||'END';
    }

#    print Dumper($staffHash); # $cvHash, $dtColCode);
    my $API_URL = $self->{endpoint};

    while (my $row = $csv->getline($fh)) {
        my $rId;
        foreach my $range (@$table_ranges) {
            my ($from, $to, $tName) = map { $range->{$_} } qw(from to name);
            my $postHash = { locale => 'en', dateFormat => 'dd MMMM yyyy' };
            foreach my $i ($from..$to) {
                my $dat = $row->[$i];
                if ($dat) {
                    my $col = $header->[$i];
                    if ("m_client" eq $tName) {
                        $col = $colKeys{$col};
                        if (my $sub = $colSub{$col}) {
                            $dat = &$sub($self, $dat);
                        }
                    } elsif ($dtColCode->{$tName}->{$col}) {
                        my $codeNm = $dtColCode->{$tName}->{$col};
                        $dat = $self->_get_code_value($codeNm, $dat);
                        $col = $codeNm . "_cd_" . $col;
                    }
                    $postHash->{$col} = $dat;
                }
            }
            if ("m_client" eq $tName) {
                print Dumper($postHash);
                $self->_do_post($API_URL . "/clients", $postHash, sub {
                    my ($content, $resp) = @_;
                    if ($resp->code =~ m/^20[01]$/) {
                        $rId = $json->decode($resp->content)->{resourceId};
                        print "Created client $rId. ";
                    } else {
                        print "Failed to import client record\n" .
                            "Request: " . $content . "\n\nResponse: " . $resp->content . "\n";
                    }
                } );
            } else {
                $self->_do_post($API_URL . "/datatables/$tName/$rId", $postHash, sub {
                    my ($content, $resp) = @_;
                    if ($resp->code =~ m/^20[01]$/) {
                        print "Added $tName"
                    } else {
                        print "Failed to import datatable $tName for client $rId\n" .
                            "Req: " . $content . "\n\nResponse: ". $resp->content . "\n";
                    }
                } );
            }
        }
    }
}

1;
