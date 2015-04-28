# Data Import tool for Mifos X

Tool to import client data from CSV spreadsheet

## Features

 * Supports client fields mobile, dob, gender
 * Supports extra client fields
 * Generates sample data format spreadsheet

## Installation

This is a Perl script and requires these libraries:

 * Config::General
 * JSON
 * LWP::UserAgent
 * Text::CSV_XS

## Usage

To run this tool, create a configuration file similar to the one below:

```
mifos.baseurl   = https://demo.openmf.org
mifos.user.id   = mifos
mifos.password  = password
mifos.tenant.id = default
```

Now to get a sample spreadsheet,

```./import-client-data.pl --config demo.conf --gensample```

The default configuration filename is ```mifosx.conf```. If the configuration
file was named so, no need to specify --config mifosx.conf.  In the sample CSV
spreadsheet, populate the client data, one per row.  To import the data,

```./import-client-data.pl sample-client-data.csv```

