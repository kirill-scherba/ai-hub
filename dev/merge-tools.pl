#!/usr/bin/env perl
use strict;
use warnings;
use JSON::PP;
use FindBin;

# Load existing tools.json
my $tools_file = "$FindBin::Bin/../tools.json";
open(my $fh, '<:utf8', $tools_file) or die "Cannot read $tools_file: $!";
local $/;
my $existing_json = <$fh>;
close $fh;
my $existing = decode_json($existing_json);

# Index existing by name
my %existing_by_name;
for my $t (@$existing) {
    $existing_by_name{$t->{name}} = $t;
}

# Load tool definitions
require "$FindBin::Bin/github-tools.pl";
my $definitions = get_all_github_tools();

# Merge: keep existing, add missing ones with proper format
my $now = do {
    my @tm = localtime;
    sprintf("%04d-%02d-%02d %02d:%02d:%02d",
        $tm[5]+1900, $tm[4]+1, $tm[3], $tm[2], $tm[1], $tm[0]);
};

my $added = 0;
for my $d (@$definitions) {
    my $name = $d->{name};
    next if $existing_by_name{$name};
    
    push @$existing, {
        name        => $name,
        description => $d->{description},
        inputSchema => $d->{inputSchema},
        code        => $d->{code},
        source      => 'github-tools',
        created_at  => $now,
    };
    $added++;
}

# Write updated tools.json
my $json = JSON::PP->new->pretty->canonical;
my $content = $json->encode($existing);
open(my $out, '>:utf8', $tools_file) or die "Cannot write $tools_file: $!";
print $out $content;
close $out;

print "Updated tools.json: $added tools added, " . scalar(@$existing) . " total.\n";