#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use JSON;

binmode(STDIN,  ":utf8");
binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

my $json = JSON->new->allow_nonref;

use IPC::Open2;
my ($child_rdr, $child_wtr);
my $pid = open2($child_rdr, $child_wtr, "perl /home/kirill/go/src/github.com/kirill-scherba/ai-hub/generative-mcp-hub.pl 2>/tmp/hub_debug.log");

binmode($child_rdr, ":utf8");
binmode($child_wtr, ":utf8");

sub send_raw {
    my ($msg) = @_;
    print $child_wtr $json->encode($msg) . "\n";
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

# Init
send_raw({ jsonrpc => "2.0", id => 1, method => "initialize", params => {} });
my $notif = recv_raw();
my $init_resp = recv_raw();
print "INIT: " . (eval { $json->decode($init_resp)->{result}{serverInfo}{name} } // 'FAIL') . "\n";

# === TEST: Cyrillic round-trip through sandbox ===
my $code_cyrillic = <<'PERL_CODE';
return {
    message => $args->{text},
    original_length => length($args->{text}),
    upper_case => uc($args->{text}),
    greeting => "Привет, мир! Сообщение: " . ($args->{text} // ""),
};
PERL_CODE

my $gen = send_recv({
    jsonrpc => "2.0", id => 2, method => "tools/call",
    params => {
        name => "tool_generate",
        arguments => {
            name => "cyrillic_test",
            description => "Test cyrillic round-trip",
            inputSchema => { type => "object", properties => { text => { type => "string" } } },
            code => $code_cyrillic,
        },
    },
});
my $gen_decoded = $json->decode($gen);
print "GENERATE: " . (eval { $json->decode($gen_decoded->{result}{content}[0]{text})->{data} } // 'FAIL') . "\n";

# Test with cyrillic
my $resp = send_recv({
    jsonrpc => "2.0", id => 3, method => "tools/call",
    params => { name => "cyrillic_test", arguments => { text => "Привет, Кирилл! Как дела? 你好" } },
});
my $resp_decoded = $json->decode($resp);
my $inner = eval { $json->decode($resp_decoded->{result}{content}[0]{text}) };
if ($inner && $inner->{data}) {
    print "RESULT:\n";
    print $json->pretty->encode($inner->{data}) . "\n";
    
    # Verify
    my $d = $inner->{data};
    if ($d->{message} eq "Привет, Кирилл! Как дела? 你好") {
        print "✓  Cyrillic round-trip OK\n";
    } else {
        print "✗  MISMATCH: got '$d->{message}'\n";
    }
    if ($d->{uppercase} eq "ПРИВЕТ, КИРИЛЛ! КАК ДЕЛА? 你好") {
        print "✓  uc() on cyrillic OK\n";
    } else {
        print "✗  uc MISMATCH: got '$d->{uppercase}'\n";
    }
    if (index($d->{greeting}, "Привет, мир!") == 0) {
        print "✓  Embedded cyrillic in code OK\n";
    }
} else {
    print "RAW: $resp\n";
}

close($child_wtr);
waitpid($pid, 0);