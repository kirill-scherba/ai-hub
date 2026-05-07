#!/usr/bin/env perl
# =============================================================================
# Generate all 12 GitHub tools via tool_generate
#
# Usage: GITHUB_TOKEN=ghp_xxx perl dev/generate-all-tools.pl
#
# This script:
#   1. Loads the tool definitions from dev/github-tools.pl
#   2. Starts generative-mcp-hub.pl as a subprocess
#   3. Sends 12 tool_generate JSON-RPC requests
#   4. Verifies the tools were created
#   5. Saves the tools.json
# =============================================================================
use strict;
use warnings;
use JSON;
use IO::Socket;
use File::Basename qw(dirname);
use Cwd qw(abs_path);

my $JSON = JSON->new->utf8->allow_nonref;

# Paths
my $HUB_DIR  = dirname(dirname(abs_path($0)));
my $HUB_BIN  = "$HUB_DIR/generative-mcp-hub.pl";
my $TOOLS_PM = "$HUB_DIR/dev/github-tools.pl";

# Load tool definitions
require $TOOLS_PM;
my $tools = get_all_github_tools();

print "Loaded " . scalar(@$tools) . " tool definitions from $TOOLS_PM\n";

# Start generative-mcp-hub.pl as a subprocess
use IPC::Open2;
my ($child_in, $child_out);
my $pid = open2($child_out, $child_in, $^X, $HUB_BIN)
    or die "Cannot start $HUB_BIN: $!";

# Set binmode for UTF-8
binmode($child_in,  ':utf8');
binmode($child_out, ':utf8');

print "Started ai-hub (PID: $pid)\n";

# Wait for the "initialized" notification
my $initialized;
while (<$child_out>) {
    chomp;
    my $msg = eval { $JSON->decode($_) };
    next unless $msg;
    if ($msg->{method} && $msg->{method} eq 'initialized') {
        $initialized = 1;
        print "Hub server initialized\n";
        last;
    }
}
die "Hub server did not initialize" unless $initialized;

# Function to send a JSON-RPC request and get the response
sub send_request {
    my ($method, $params) = @_;
    my $id = int(rand(10000)) + 1;
    my $req = { jsonrpc => '2.0', id => $id, method => $method };
    $req->{params} = $params if $params;
    print $child_in $JSON->encode($req) . "\n";
    $child_in->flush();
    
    # Read response (might need to skip notifications)
    while (<$child_out>) {
        chomp;
        my $msg = eval { $JSON->decode($_) };
        next unless $msg && ref $msg eq 'HASH';
        return $msg if $msg->{id} && $msg->{id} == $id;
        # It might be a notification, skip
    }
    return undef;
}

# Send tool_generate for each tool
my $generated = 0;
my $failed    = 0;

for my $tool (@$tools) {
    print "\nGenerating tool: $tool->{name}... ";
    
    my $resp = send_request('tools/call', {
        name => 'tool_generate',
        arguments => {
            name        => $tool->{name},
            description => $tool->{description},
            inputSchema => $tool->{inputSchema},
            code        => $tool->{code},
            source      => 'github-tools',
        },
    });
    
    if ($resp && $resp->{result}) {
        my $text = $resp->{result}{content}[0]{text} // '';
        if ($text =~ /success/) {
            print "OK\n";
            $generated++;
        } else {
            print "UNEXPECTED: $text\n";
            $failed++;
        }
    } elsif ($resp && $resp->{error}) {
        print "ERROR: " . $resp->{error}{message} . "\n";
        $failed++;
    } else {
        print "NO RESPONSE\n";
        $failed++;
    }
}

print "\n" . ("=" x 50) . "\n";
print "Generated: $generated / " . scalar(@$tools) . " tools\n";
print "Failed:    $failed\n" if $failed;
print ("=" x 50) . "\n";

# Verify by listing tools
print "\nVerifying generated tools...\n";
my $list_resp = send_request('tools/call', {
    name => 'tool_list',
    arguments => {},
});
if ($list_resp && $list_resp->{result}) {
    my $text = $list_resp->{result}{content}[0]{text} // '';
    my $data = eval { $JSON->decode($text) };
    if ($data && $data->{status} eq 'success') {
        my @generated = grep { $_->{source} && $_->{source} eq 'github-tools' } @{$data->{data}{generated} // []};
        print "Verified " . scalar(@generated) . " github-tools in registry\n";
    }
}

# Close the subprocess
close($child_in);
close($child_out);
waitpid($pid, 0);

print "\nDone. Check $HUB_DIR/tools.json for persisted tools.\n";