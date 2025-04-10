#!/usr/bin/perl
#===============================================================================
#
#         FILE:  mine.pl
#
#        USAGE:  ./mine.pl [options] file1 file2 ...
#
#  DESCRIPTION:
#       This script extracts energy values from Gaussian output files and calculates
#       either relative or total energies. It ensures that the energies are compared
#       at the same level of theory and (if available) the same temperature. It supports
#       file grouping (up to five groups, via options --g1 through --g5), unit conversions,
#       precision formatting, optional solvent corrections, and prints key common
#       program information (temperature, method, and basis set) in a header.
#
#       When the option --terse is provided, the summary header is omitted,
#       and only the final energies are printed.
#
#      OPTIONS:
#         --help, -h        : Display this help message.
#         --g1 <file> ...   : Files in group 1.
#         --g2 <file> ...   : Files in group 2.
#         --g3 <file> ...   : Files in group 3.
#         --g4 <file> ...   : Files in group 4.
#         --g5 <file> ...   : Files in group 5.
#         --zero=<key>      : Specify the reference file (or group key; e.g., "1" for group 1)
#                             whose energy is set to zero.
#         --td <td_function>: Choose the energy extraction method (e.g., ent, ezpe, Gibbs, scf, etc.).
#         --precision=<num> : Set the number of decimal places in the output.
#         --toten          : Print total (absolute) energies (no relative shift) and sets precision to 6.
#         --kJ             : Convert energies to kilojoules per mol.
#         --cm             : Convert energies to wavenumbers (cm^-1).
#         --ev             : Convert energies to electronvolts (precision 3).
#         --nosort         : Do not sort the output.
#         --solvent        : Apply a solvent conversion factor for free energies.
#         --verbose        : Display detailed internal processing messages.
#         --terse          : Print only final energies without summary header.
#
#      REQUIREMENTS:  Gaussian output files.
#         BUGS:  None known.
#        NOTES:
#       AUTHOR:  Marat Talipov (Dr.), talipovm@nmsu.edu
#      COMPANY:  New Mexico State University
#      VERSION:  1.9  (Added descriptive help option)
#      CREATED:  10/03/2011 18:31:26
#     REVISION:  2025-04-09
#===============================================================================

use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;

#------------------------------------------------------------------------------
# Define energy extraction patterns for different energy types from Gaussian outputs.
#------------------------------------------------------------------------------
my %energy_extract_patterns = (
    ent         => 'Sum of electronic and thermal Enthalpies=\s+(\S+)',
    ezpe        => 'Sum of electronic and zero-point Energies=\s+(\S+)',
    Gibbs       => 'Sum of electronic and thermal Free Energies=\s+(\S+)',
    ent_cbs_qb3 => 'CBS-QB3 Enthalpy=\s+(\S+)',
    e0_cbs_qb3  => 'CBS-QB3 \(0 K\)=\s+(\S+)',
    e_cbs_qb3   => 'CBS-QB3 Energy=\s+(\S+)',
    g_cbs_qb3   => 'CBS-QB3 Free Energy=\s+(\S+)',
    scf         => 'SCF Done: .*?=\s+(\S+)',
);

#------------------------------------------------------------------------------
# Free energy types that might need a solvent conversion adjustment.
#------------------------------------------------------------------------------
my %free_energy_types = (
    'Gibbs'     => '',
    'g_cbs_qb3' => ''
);

#------------------------------------------------------------------------------
# Global defaults and command-line option variables.
#------------------------------------------------------------------------------
my $help          = 0;    # Flag for displaying help.
my $zero_ref      = '';   # The reference file or group key (via --zero)
my $combined_zero_energy; # Zero reference energy from a group (if applicable)
my $unit_conv     = 1;    # Conversion factor (default: kcal/mol)
my $print_total   = 0;    # Flag: print total energies (no relative shift)
my $precision     = 1;    # Default output precision (decimal places)
my $td_function   = 'ent';# Default energy extraction key (e.g., 'ent')
my $apply_solvent = 0;    # Solvent conversion factor (if requested)
my $no_sort       = 0;    # Flag: do not sort output
my $verbose       = 0;    # Verbose mode for extra processing messages
my $terse         = 0;    # Terse output flag (skip summary header)

# Static group options for up to five groups:
my @g1;
my @g2;
my @g3;
my @g4;
my @g5;

#------------------------------------------------------------------------------
# Process command-line options.
#------------------------------------------------------------------------------
GetOptions(
    'help|h'      => \$help,
    'g1=s@'       => \@g1,
    'g2=s@'       => \@g2,
    'g3=s@'       => \@g3,
    'g4=s@'       => \@g4,
    'g5=s@'       => \@g5,
    'zero=s'      => \$zero_ref,
    'td=s'        => \$td_function,
    'precision=s' => \$precision,
    'toten'       => sub { $print_total = 1; $precision = 6 },
    'kJ'          => sub { $unit_conv = 4.184 },
    'cm'          => sub { $unit_conv = 349.757 },
    'ev'          => sub { $unit_conv = 1/23.06; $precision = 3 },
    'nosort'      => \$no_sort,
    'solvent'     => sub { $apply_solvent = 1.89/627.509 },
    'verbose'     => \$verbose,
    'terse'       => \$terse,
) or die "Error processing command line options.\n";

#------------------------------------------------------------------------------
# If help flag is set or no input files are provided, display usage information.
#------------------------------------------------------------------------------
if ( $help or ( !@ARGV && !@g1 && !@g2 && !@g3 && !@g4 && !@g5 ) ) {
    print_help();
    exit;
}

#------------------------------------------------------------------------------
# Print starting message if verbose.
#------------------------------------------------------------------------------
print "Starting energy extraction process...\n" if $verbose;

#------------------------------------------------------------------------------
# Determine unit string for final output based on conversion factor.
#------------------------------------------------------------------------------
my $unit_str;
if ($unit_conv == 1) {
    $unit_str = "kcal/mol";
} elsif ($unit_conv == 4.184) {
    $unit_str = "kJ/mol";
} elsif ($unit_conv == 349.757) {
    $unit_str = "cm^-1";
} elsif (abs($unit_conv - (1/23.06)) < 0.0001) {
    $unit_str = "eV";
} else {
    $unit_str = "unknown unit";
}

#------------------------------------------------------------------------------
# Validate that the specified thermal energy extraction function exists.
#------------------------------------------------------------------------------
unless (exists $energy_extract_patterns{$td_function}) {
    print "Error: '$td_function' key not found.\n";
    print "Registered keys: " . join(", ", sort keys %energy_extract_patterns) . "\n";
    exit(1);
}

#------------------------------------------------------------------------------
# Gather list of Gaussian output files from command-line arguments.
#------------------------------------------------------------------------------
# Start with any files given as positional arguments.
my @file_list = @ARGV;
# Add files from group options.
push @file_list, @g1, @g2, @g3, @g4, @g5;
print "Initial file list: " . join(", ", @file_list) . "\n" if $verbose;

#------------------------------------------------------------------------------
# Remove duplicate files.
#------------------------------------------------------------------------------
my %unique_files = map { $_ => 1 } @file_list;

#------------------------------------------------------------------------------
# Extract energy values, temperatures, method, and basis set from each Gaussian output file.
#------------------------------------------------------------------------------
my %file_energies;
foreach my $file (keys %unique_files) {
    print "Processing file: $file\n" if $verbose;
    my ($extracted_ref, $method, $basis) = extract_energy($file);
    my @temps = sort { $a <=> $b } keys %{$extracted_ref};
    if (defined $temps[0]) {
        $file_energies{$file} = {
            energy  => $extracted_ref->{$temps[0]},
            temp    => $temps[0],
            method  => $method,
            basis   => $basis,
        };
        print "Extracted from '$file': energy = $file_energies{$file}{energy} at T = $file_energies{$file}{temp} K, method = $file_energies{$file}{method}, basis set = $file_energies{$file}{basis}\n" if $verbose;
        # Apply solvent correction if needed.
        if ($apply_solvent and exists $free_energy_types{$td_function}) {
            $file_energies{$file}{energy} += $apply_solvent;
            print "Applied solvent correction to '$file': now energy = $file_energies{$file}{energy}\n" if $verbose;
        }
    }
    else {
        warn "Error: No energy value extracted from file '$file'.\n";
    }
}

#------------------------------------------------------------------------------
# Build a hash of groups from static group options.
#------------------------------------------------------------------------------
my %grouped_files;
$grouped_files{1} = \@g1 if @g1;
$grouped_files{2} = \@g2 if @g2;
$grouped_files{3} = \@g3 if @g3;
$grouped_files{4} = \@g4 if @g4;
$grouped_files{5} = \@g5 if @g5;

#------------------------------------------------------------------------------
# Process grouping: combine energies for each specified group.
#------------------------------------------------------------------------------
my %files_to_remove;
foreach my $group_number (keys %grouped_files) {
    my $combined_key    = "";
    my $combined_energy = 0;
    my (%group_methods, %group_bases, %group_temps);
    my @files_in_group = @{$grouped_files{$group_number}};
    foreach my $filename (@files_in_group) {
        next unless exists $file_energies{$filename};
        $combined_key .= "+$filename";
        $combined_energy += $file_energies{$filename}{energy};
        $group_methods{ $file_energies{$filename}{method} } = 1;
        $group_bases{ $file_energies{$filename}{basis} } = 1;
        $group_temps{ $file_energies{$filename}{temp} } = 1;
        $files_to_remove{$filename} = 1;
    }
    # Determine the group's common method.
    my $group_method;
    if (scalar(keys %group_methods) == 1) {
        ($group_method) = keys %group_methods;
    } else {
        $group_method = "Mixed: " . join(", ", sort keys %group_methods);
        warn "Warning: Group $group_number has inconsistent methods: " . join(", ", sort keys %group_methods) . "\n";
    }
    # Determine the group's common basis set.
    my $group_basis;
    if (scalar(keys %group_bases) == 1) {
        ($group_basis) = keys %group_bases;
    } else {
        $group_basis = "Mixed: " . join(", ", sort keys %group_bases);
        warn "Warning: Group $group_number has inconsistent basis sets: " . join(", ", sort keys %group_bases) . "\n";
    }
    # Determine the group's common temperature.
    my $group_temp;
    if (scalar(keys %group_temps) == 1) {
        ($group_temp) = keys %group_temps;
    } else {
        $group_temp = "Mixed: " . join(", ", sort { $a <=> $b } keys %group_temps);
        warn "Warning: Group $group_number has inconsistent temperatures: " . join(", ", sort { $a <=> $b } keys %group_temps) . "\n";
    }
    # Store the merged information.
    $file_energies{$combined_key} = {
        energy => $combined_energy,
        temp   => $group_temp,
        method => $group_method,
        basis  => $group_basis,
    };
    print "Group $group_number combined files: " . join(", ", @files_in_group) .
          " => Combined energy: $combined_energy, temperature: $group_temp, method: $group_method, basis: $group_basis\n" if $verbose;
    if ($zero_ref eq $group_number) {
        $combined_zero_energy = $combined_energy;
        print "Zero reference set by group $group_number with energy: $combined_energy\n" if $verbose;
    }
}

# Remove individual files that were grouped.
foreach my $fname (keys %files_to_remove) {
    delete $file_energies{$fname};
    print "Removed individual file '$fname' as part of a grouped set\n" if $verbose;
}

#------------------------------------------------------------------------------
# Check for consistency of method across all files.
#------------------------------------------------------------------------------
my %method_set;
foreach my $key (keys %file_energies) {
    my $method = $file_energies{$key}{method};
    $method_set{$method} = 1;
}
my @common_methods = keys %method_set;
my $common_method;
if (@common_methods == 1) {
    $common_method = $common_methods[0];
} else {
    $common_method = "Inconsistent: " . join(", ", sort @common_methods);
    warn "Warning: Inconsistent methods detected among files: $common_method\n";
}

#------------------------------------------------------------------------------
# Check for consistency of basis set across all files.
#------------------------------------------------------------------------------
my %basis_set;
foreach my $key (keys %file_energies) {
    my $basis = $file_energies{$key}{basis};
    $basis_set{$basis} = 1;
}
my @common_bases = keys %basis_set;
my $common_basis;
if (@common_bases == 1) {
    $common_basis = $common_bases[0];
} else {
    $common_basis = "Inconsistent: " . join(", ", sort @common_bases);
    warn "Warning: Inconsistent basis sets detected among files: $common_basis\n";
}

#------------------------------------------------------------------------------
# Check for consistency of temperature across all files.
#------------------------------------------------------------------------------
my %temp_set;
foreach my $key (keys %file_energies) {
    my $temp = $file_energies{$key}{temp};
    if (defined $temp and $temp ne "") {
        $temp_set{$temp} = 1;
    }
}
my @common_temps = keys %temp_set;
my $common_temp;
if (@common_temps == 0) {
    $common_temp = "Not available";
} elsif (@common_temps == 1) {
    $common_temp = sprintf("%.2f K", $common_temps[0]);
} else {
    $common_temp = "Inconsistent: " . join(", ", sort { $a <=> $b } @common_temps);
    warn "Warning: Inconsistent temperatures detected among files: $common_temp\n";
}

#------------------------------------------------------------------------------
# Determine the minimum energy (the reference energy).
#------------------------------------------------------------------------------
my @energy_values = sort { $a <=> $b } map { $_->{energy} } values %file_energies;
my $min_energy = $energy_values[0];

if ($zero_ref and exists $file_energies{$zero_ref}) {
    $min_energy = $file_energies{$zero_ref}{energy};
    print "Zero reference provided: using '$zero_ref' with energy $min_energy\n" if $verbose;
}
if (defined $combined_zero_energy) {
    $min_energy = $combined_zero_energy;
    print "Zero reference (group override): using grouped energy $min_energy\n" if $verbose;
}
print "Minimum energy (reference) determined as: $min_energy\n" if $verbose;

#------------------------------------------------------------------------------
# Calculate energies for output.
#------------------------------------------------------------------------------
foreach my $key (keys %file_energies) {
    if (defined $file_energies{$key}{energy} and not $print_total) {
        $file_energies{$key}{energy} =
            ($file_energies{$key}{energy} - $min_energy) * 627.509 * $unit_conv;
    }
}

#------------------------------------------------------------------------------
# Optionally print summary header (unless --terse is specified).
#------------------------------------------------------------------------------
unless ($terse) {
    print "\n--------------------------------------------\n";
    print "Summary Information:\n";
    print "Units:                $unit_str\n";
    print "Calculation Mode:     " . ($print_total ? "Total Energies" : "Relative Energies") . "\n";
    print "Sorting:              " . ($no_sort ? "Unsorted" : "Sorted (lowest to highest)") . "\n";
    print "Thermal Extraction:   $td_function\n";
    print "Temperature:          $common_temp\n";
    print "Method:               $common_method\n";
    print "Basis Set:            $common_basis\n";
    print "Solvent/Grid/etc      Not Analyzed (you need to check it manually)\n";
    print "--------------------------------------------\n";
}

#------------------------------------------------------------------------------
# Output the final results.
#------------------------------------------------------------------------------
if ($no_sort) {
    foreach my $key (sort keys %file_energies) {
        printf "%-40s %10.${precision}f\n", $key, $file_energies{$key}{energy};
    }
} else {
    foreach my $key (sort { $file_energies{$a}{energy} <=> $file_energies{$b}{energy} } keys %file_energies) {
        printf "%-40s %10.${precision}f\n", $key, $file_energies{$key}{energy};
    }
}

#===============================================================================
# Subroutine: extract_energy
#
# DESCRIPTION:
#   Reads a Gaussian output file (with '~' expanded) and extracts the desired
#   energy value using the pattern specified by $td_function. It also attempts to
#   extract:
#     - The basis set from a line containing "Standard basis:" (case-insensitive).
#     - The method from a "SCF Done:" line (the method appears within parentheses).
#   These are returned separately.
#
#   Additionally, the subroutine extracts temperature information (default 298.15 K
#   if not found) and stores energies keyed by temperature. Temperatures are normalized
#   to two decimal places.
#
# ARGUMENT:
#   $filename - Path to the Gaussian output file.
#
# RETURNS:
#   A three-element list:
#     1. A hash reference where each key is a temperature and the corresponding value is the extracted energy.
#     2. A string representing the method.
#     3. A string representing the basis set.
#===============================================================================
sub extract_energy {
    my ($filename) = @_;
    my %thermal_data;
    my $method = "";
    my $basis  = "";

    # Expand '~' in the file path using the home directory.
    my $home = $ENV{HOME} || (getpwuid($<))[7];
    $filename =~ s/~/$home/;

    # Open the file.
    open my $fh, '<', $filename or do {
        warn "Could not open file '$filename': $!\n";
        return (\%thermal_data, $method, $basis);
    };

    # Default temperature (298.15 K formatted to two decimals)
    my $current_temp = sprintf("%.2f", 298.15);

    while (my $line = <$fh>) {
        # Extract basis set (case-insensitive).
        if ($line =~ /Standard basis:\s*(\S.*)/i) {
            $basis = $1;
            $basis =~ s/\s+$//;  # trim trailing whitespace
        }
        # Extract method.
        if (!$method and $line =~ /SCF Done:.*?E\((\S+?)\)/) {
            $method = $1;
        }
        # Update temperature if found.
        if ($line =~ /Temperature\s+(\S+)\s+Kelvin.*Pressure/) {
            $current_temp = sprintf("%.2f", $1);
        }
        # Extract energy using the chosen pattern.
        if ($line =~ /$energy_extract_patterns{$td_function}/) {
            $thermal_data{$current_temp} = $1;
        }
    }
    close $fh;

    return (\%thermal_data, $method, $basis);
}

#===============================================================================
# Subroutine: print_help
#
# DESCRIPTION:
#   Prints a detailed usage message explaining how to use this script and its options.
#===============================================================================
sub print_help {
    print <<'END_HELP';
Usage: mine.pl [options] file1 file2 ...

Description:
  This script extracts energy values from Gaussian output files and calculates either relative or total energies.
  It supports comparing energies at the same level of theory and temperature, file grouping (up to five groups via --g1 .. --g5),
  unit conversions, precision formatting, and optional solvent corrections. The script also prints summary information including
  temperature, method, and basis set unless the --terse option is specified.

Options:
  --help, -h         Display this help message.
  --g1 <file> ...    Files in group 1.
  --g2 <file> ...    Files in group 2.
  --g3 <file> ...    Files in group 3.
  --g4 <file> ...    Files in group 4.
  --g5 <file> ...    Files in group 5.
  --zero=<key>       Specify the reference file (or group key) whose energy is set to zero.
  --td <td_function> Choose the energy extraction method (e.g., ent, ezpe, Gibbs, scf, etc.). Default: ent.
  --precision=<num>  Set the number of decimal places in the output. Default: 1.
  --toten           Print total (absolute) energies (no relative shift) and sets precision to 6.
  --kJ              Convert energies to kilojoules per mol.
  --cm              Convert energies to wavenumbers (cm^-1).
  --ev              Convert energies to electronvolts (precision set to 3).
  --nosort          Do not sort the output.
  --solvent         Apply a solvent conversion factor for free energies.
  --verbose         Display detailed internal processing messages.
  --terse           Print only final energies without a summary header.

Examples:
  ./mine.pl --td=Gibbs --kJ file1.log file2.log
  ./mine.pl --g1 file1.log file2.log --g2 file3.log --zero=1 --verbose

END_HELP
}
