#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";

# Load the hub server (this will set up &generate_tool, &save_tools, %tool_registry)
# We load it in "batch mode" — we set an env var to prevent server start
$ENV{AI_HUB_BATCH} = 1;
require "$FindBin::Bin/../generative-mcp-hub.pl";

# Load our tool definitions
require "$FindBin::Bin/github-tools.pl";
my $tools = get_all_github_tools();

my $count = 0;
for my $t (@$tools) {
    my $name = $t->{name};
    next unless $name;

    # Already in registry?
    if ($tool_registry{$name}) {
        print "[SKIP] $name already registered\n";
        next;
    }

    print "[GEN ] $name...\n";
    my $result = generate_tool(
        $name,
        $t->{description},
        $t->{inputSchema},
        $t->{code},
    );

    if ($result) {
        $count++;
        print "[OK  ] $name\n";
    } else {
        print "[FAIL] $name\n";
    }
}

if ($count > 0) {
    save_tools();
    print "\nSaved $count new tools to tools.json\n";
} else {
    print "\nNo new tools to generate.\n";
}