#!/usr/bin/env perl
use strict;
use warnings;
use JSON::PP;

require "/home/kirill/go/src/github.com/kirill-scherba/ai-hub/dev/github-tools.pl";
my $tools = get_all_github_tools();

# Output only metadata (no code) for listing
print encode_json($tools);