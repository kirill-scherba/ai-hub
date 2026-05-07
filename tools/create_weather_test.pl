#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use JSON;

binmode(STDIN,  ":utf8");
binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

my $json = JSON->new->utf8->allow_nonref->canonical;
$json->indent(0);  # compact output
my $json_pretty = JSON->new->utf8->allow_nonref->canonical->pretty(1);

# Start hub with bidirectional communication (stderr to file for debugging)
use IPC::Open2;
my ($child_rdr, $child_wtr);
my $logfile = "/tmp/hub_debug.log";
unlink $logfile if -f $logfile;
my $pid = open2($child_rdr, $child_wtr, "perl /home/kirill/go/src/github.com/kirill-scherba/ai-hub/generative-mcp-hub.pl 2>$logfile");

binmode($child_rdr, ":utf8");
binmode($child_wtr, ":utf8");

sub send_raw {
    my ($msg) = @_;
    my $encoded = $json->encode($msg);
    my $has_nl = ($encoded =~ tr/\n//);
    print STDERR "SEND (len=" . length($encoded) . ", nl=$has_nl): " . substr($encoded, 0, 300) . "\n";
    print $child_wtr $encoded . "\n";
    $child_wtr->flush();
}

sub recv_raw {
    my $line = <$child_rdr>;
    chomp $line if $line;
    return $line;
}

sub send_recv {
    my ($msg) = @_;
    send_raw($msg);
    return recv_raw();
}

sub show_stderr {
    if (open(my $fh, '<', $logfile)) {
        my @lines = <$fh>;
        close $fh;
        print "--- STDERR LOG ---\n";
        print @lines;
        print "--- END STDERR ---\n";
    }
}

# Init
send_raw({ jsonrpc => "2.0", id => 1, method => "initialize", params => {} });
my $notif = recv_raw();
my $init_resp = recv_raw();
print "INIT: " . (eval { $json->decode($init_resp)->{result}{serverInfo}{name} } // 'FAIL') . "\n";

# === TEST 1: Simple tool with no HTTP, no JSON::decode_json ===
print "\n=== TEST 1: Simple return hashref ===\n";
my $code1 = <<'PERL_CODE';
return { message => "Hello!", city => ($args->{city} // "unknown") };
PERL_CODE

my $gen1 = send_recv({
    jsonrpc => "2.0", id => 2, method => "tools/call",
    params => {
        name => "tool_generate",
        arguments => {
            name => "simple",
            description => "Simple test",
            inputSchema => { type => "object", properties => { city => { type => "string" } } },
            code => $code1,
        },
    },
});
my $gen1_decoded = $json->decode($gen1);
print "GEN1: " . (eval { $json->decode($gen1_decoded->{result}{content}[0]{text})->{data} } // 'FAIL') . "\n";

my $t1 = send_recv({
    jsonrpc => "2.0", id => 3, method => "tools/call",
    params => { name => "simple", arguments => { city => "Berlin" } },
});
my $t1d = $json->decode($t1);
print "T1 RAW: $t1\n";
my $t1_inner = eval { $json->decode($t1d->{result}{content}[0]{text}) };
if ($t1_inner) {
    print "T1 status: " . ($t1_inner->{status} // '?') . "\n";
    if ($t1_inner->{data}) {
        print "T1 data: " . $json_pretty->encode($t1_inner->{data}) . "\n";
    } else {
        print "T1 data is: " . (defined $t1_inner->{data} ? "defined but falsy" : "undef") . "\n";
    }
}

# === TEST 2: Weather tool with _safe_http_get ===
print "\n=== TEST 2: Weather with _safe_http_get ===\n";
my $code2 = 'my $c = $args->{city} or die "no city"; $c =~ s/ /+/g; my $r = _safe_http_get("https://wttr.in/$c?format=j1"); die "HTTP $r->{status}" unless $r->{success}; my $d = _safe_decode_json($r->{content}); my $cur = $d->{current_condition}[0]; return { city => ($d->{nearest_area}[0]{areaName}[0]{value} // $c), temp_c => $cur->{temp_C} + 0 }';
# Remove all newlines from code so JSON stays on one line (hub reads line-by-line)
$code2 =~ s/\n//g;
$code2 =~ s/\r//g;

my $gen2 = send_recv({
    jsonrpc => "2.0", id => 4, method => "tools/call",
    params => {
        name => "tool_generate",
        arguments => {
            name => "weather",
            description => "Get weather via wttr.in",
            inputSchema => { type => "object", properties => { city => { type => "string" } }, required => ["city"] },
            code => $code2,
        },
    },
});
my $gen2_decoded = $json->decode($gen2);
print "GEN2: " . (eval { $json->decode($gen2_decoded->{result}{content}[0]{text})->{data} } // 'FAIL') . "\n";

my $t2 = send_recv({
    jsonrpc => "2.0", id => 5, method => "tools/call",
    params => { name => "weather", arguments => { city => "Berlin" } },
});
my $t2d = $json->decode($t2);
my $t2_inner = eval { $json->decode($t2d->{result}{content}[0]{text}) };
if ($t2_inner && $t2_inner->{data}) {
    print "T2 weather data: " . $json_pretty->encode($t2_inner->{data}) . "\n";
} else {
    print "T2 RAW: $t2\n";
    print "T2 inner: " . ($t2_inner ? $json->encode($t2_inner) : 'FAIL') . "\n";
}

show_stderr();

close($child_wtr);
waitpid($pid, 0);