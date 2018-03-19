#!/usr/bin/perl

use strict;
use Text::CSV;

die "Usage: ./myCSV2SQL.pl <filename> <tablename>" if !@ARGV[0] || !@ARGV[1];

my $inputFileName = @ARGV[0];
my $tableName = @ARGV[1];
my $outputFileName = $tableName . ".sql";

my $csv = Text::CSV->new ({ binary => 1, auto_diag => 1, diag_verbose => 1 }) or die "Cannot use CSV: ".Text::CSV->error_diag ();
open my $fh, "<:encoding(UTF-8)", $inputFileName or die "Can't open input file: $inputFileName ($!)";

my $isFirstRow = 1;
my @columnNames;
my @columnSizes;
my @columnTypes;
my $totalColumns = 0;

my @values;

while (my $row = $csv->getline($fh)) {
    
    # First row
    if ($isFirstRow) {
        @columnNames = @$row;
        $totalColumns = @columnNames;
        $isFirstRow = 0;
    }
    
    # Other rows
    else {
        
        push @values, $row;
        
        my $valuesIndex = 0;
        foreach my $value (@$row) {

            # First, lets find out and update (if necessary) the column size
            
            my $currentValueSize = length($value);
            my $knownColumnSize = @columnSizes[$valuesIndex];
            
            if ($currentValueSize > $knownColumnSize) {
                @columnSizes[$valuesIndex] = $currentValueSize;
            }
            
            # Then, lets find out and update (if necessary) the column type
            
            my $currentValueType;
            
            # NULL
            if (isNullValue($value)) {
                $currentValueType = undef;
            }
            
            # INT or BIGINT
            elsif ($value =~ /^[\-]*[0-9]+$/ && $value < 9223372036854775807) { # Even BIGINT's are not that bigger!
                if ($value >= -2147483648 && $value <= 2147483647) {
                    $currentValueType = 'INT';
                } else {
                    $currentValueType = 'BIGINT';
                }
            }
            
            # DOUBLE
            elsif ($value =~ /^[\-]*[0-9]+\.[0-9]+$/) {
                $currentValueType = 'DOUBLE';
            }
            
            # DATETIME
            elsif ($value =~ /^\d\d\d\d-\d\d-\d\d/) {
                $currentValueType = 'DATETIME';
            }
            
            # VARCHAR
            else {
                $currentValueType = 'VARCHAR';
            }
            
            my $knownColumnType = @columnTypes[$valuesIndex];
            
            # If the column type is still unknown
            if (!$knownColumnType) {
                @columnTypes[$valuesIndex] = $currentValueType;
            }
            
            # If known type is already VARCHAR, VARCHAR stays (current type is ignored)
            elsif ($knownColumnType =~ /VARCHAR/) {
                @columnTypes[$valuesIndex] = $knownColumnType;
            }
            
            # If current type is VARCHAR, VARCHAR must be
            elsif ($currentValueType =~ /VARCHAR/) {
                @columnTypes[$valuesIndex] = $currentValueType;
            }
            
            # If current type is not VARCHAR (previously checked) and is DOUBLE, DOUBLE must be
            elsif ($currentValueType =~ /DOUBLE/) {
                @columnTypes[$valuesIndex] = $currentValueType;
            }
            
            # If current type is not VARCHAR or DOUBLE (previously checked) and is BIGINT, BIGINT must be
            elsif ($currentValueType =~ /BIGINT/) {
                @columnTypes[$valuesIndex] = $currentValueType;
            }

            $valuesIndex++;
        }
    }
    
}

$csv->eof or $csv->error_diag();
close $fh;


# Print CREATE statement

my $columnIndex = 0;
my %usedColumnNames;

open OUTPUT, ">:encoding(UTF-8)", $outputFileName;

print OUTPUT "-- Total columns: $totalColumns\n\n";
print OUTPUT "DROP TABLE IF EXISTS $tableName;\n\n";
print OUTPUT "CREATE TABLE $tableName (\n";

foreach my $columnName (@columnNames) {
    
    $columnName = lc($columnName);
    $columnName =~ s/:/_/g;
    
    if (length($columnName) > 64) {
        $columnName = "TRUNCATED_" . $columnIndex . "_" . $columnName ;
        $columnName = substr($columnName,0,64);
    }
    
    if ($usedColumnNames{$columnName}) {
        $columnName = "REPEATED_" . $columnIndex . "_" . $columnName;
        $columnName = substr($columnName,0,64);
    }
    $usedColumnNames{$columnName} = 1;
    
    my $columnType = @columnTypes[$columnIndex];
    my $columnSize = @columnSizes[$columnIndex];
    if (!$columnType) {
        $columnType = 'VARCHAR';
        $columnSize = 1;
    }
    
    print OUTPUT "\t" . $columnName . " " . $columnType;
    if ($columnType =~ /VARCHAR/) {
        print OUTPUT "(" . $columnSize . ")";
    }
    $columnIndex++;
    if ($columnIndex < $totalColumns) {
        print OUTPUT ",";
    }
    print OUTPUT "\n";
}
print OUTPUT ");\n\n";

# Print INSERT statements

foreach my $row (@values) {
    print OUTPUT "INSERT INTO $tableName VALUES (\n";
    my $valuesIndex = 0;
    foreach my $columnName (@columnNames) {
        
        my $value = @$row[$valuesIndex];
        my $columnType = @columnTypes[$valuesIndex];
        
        if (!$columnType) {
            $columnType = 'VARCHAR';
        }

        # NULL
        if (isNullValue($value)) {
            $value = 'NULL';
        }

        # Quoted
        elsif ($columnType =~ /VARCHAR/ || $columnType =~ /DATETIME/) {
            $value = "\"" . $value . "\"";
        }
        
        # else: not quoted
        
        print OUTPUT "\t" . $value;
        
        $valuesIndex++;
        if ($valuesIndex < $totalColumns) {
            print OUTPUT ",";
        }
        
        print OUTPUT " -- " . @columnNames[$valuesIndex-1] . "\n";
        
    }
    print OUTPUT ");\n";
}

exit 1;

sub isNullValue() {
    my ($value) = @_;
    if (length($value) == 0 || $value =~ /^NULL$/ || $value =~ /^NaN$/ || $value =~ /^\.$/) {
        return 1;
    }
    return 0;
}
