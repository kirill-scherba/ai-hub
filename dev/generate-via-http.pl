#!/usr/bin/env perl
use strict;
use warnings;
use JSON::PP;
use IO::Handle;

# Load tool definitions
require "/home/kirill/go/src/github.com/kirill-scherba/ai-hub/dev/github-tools.pl";
my $tools = get_all_github_tools();

my $server = "http://localhost:5099";
my $count = 0;

for my $t (@$tools) {
    my $name = $t->{name};
    next if $name eq "github_issue_create";  # already generated in this session

    my $payload = {
        jsonrpc => "2.0",
        id => ++$count,
        method => "tools/call",
        params => {
            name => "tool_generate",
            arguments => {
                name => $name,
                description => $t->{description},
                inputSchema => $t->{inputSchema},
                code => $t->{code},
            }
        }
    };

    my $json = encode_json($payload);
    print "[$count/11] Generating $name...\n";

    open(my $fh, "-|", "curl", "-s", "-X", "POST", $server,
        "-H", "Content-Type: application/json",
        "-d", $json) or die "curl: $!";

    my $resp;
    {
        local $/;
        $resp = <$fh>;
    }
    close $fh;

    # Try to parse response
    eval {
        my $d = decode_json($resp);
        if ($d->{result} && $d->{result}->{success}) {
            print "[OK] $name generated\n";
        } elsif ($d->{error}) {
            print "[ERR] $name: $d->{error}->{message}\n";
        } else {
            print "[???] $name: " . substr($resp, 0, 200) . "\n";
        }
    };
    if ($@) {
        print "[RAW] $name: " . substr($resp, 0, 200) . "\n";
    }
}

print "\nDone. Generated $count tools (github_issue_create was already present).\n";