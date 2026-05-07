#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use JSON;
use Safe;
use IO::Select;
use IO::Handle;

binmode(STDIN,  ":utf8");
binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

my $json = JSON->new->allow_nonref;

# Open pipe to hub process
my $hub_cmd = "perl /home/kirill/go/src/github.com/kirill-scherba/ai-hub/generative-mcp-hub.pl";
open(my $hub, "|-:utf8", $hub_cmd) or die "Cannot start hub: $!";
$hub->autoflush(1);

my $sel = IO::Select->new($hub);

sub send_recv {
    my ($msg) = @_;
    my $line = $json->encode($msg);
    print $hub "$line\n";
    $hub->flush();
    my @ready = $sel->can_read(5);
    return undef unless @ready;
    my $resp = <$hub>;
    chomp $resp if $resp;
    return undef unless $resp;
    return $json->decode($resp);
}

# Initialize
my $init = send_recv({ jsonrpc => "2.0", id => 1, method => "initialize", params => {} });
print "Init: " . ($init->{result}{serverInfo}{name} // 'FAIL') . "\n";

# Test 1: Simple hello tool (no HTTP)
my $code_hello = <<'PERL_CODE';
return { message => "Hello, " . ($args->{name} // "World") . "!" };
PERL_CODE

my $gen = send_recv({
    jsonrpc => "2.0", id => 2, method => "tools/call",
    params => {
        name => "tool_generate",
        arguments => {
            name => "hello",
            description => "Simple hello test",
            inputSchema => {
                type => "object",
                properties => {
                    name => { type => "string", description => "Name" }
                },
            },
            code => $code_hello,
        },
    },
});
print "Generate hello: " . ($gen->{result}{content}[0]{text} // 'FAIL') . "\n";

my $hello = send_recv({
    jsonrpc => "2.0", id => 3, method => "tools/call",
    params => {
        name => "hello",
        arguments => { name => "Кирилл" },
    },
});
print "Hello result: " . ($hello->{result}{content}[0]{text} // 'FAIL') . "\n";

# Test 2: Simple return hashref (no use statements at all)
my $code_echo = <<'PERL_CODE';
return { input => $args->{msg} // "none" };
PERL_CODE

my $gen2 = send_recv({
    jsonrpc => "2.0", id => 4, method => "tools/call",
    params => {
        name => "tool_generate",
        arguments => {
            name => "echo",
            description => "Simple echo test",
            inputSchema => {
                type => "object",
                properties => {
                    msg => { type => "string", description => "Message" }
                },
            },
            code => $code_echo,
        },
    },
});
print "Generate echo: " . ($gen2->{result}{content}[0]{text} // 'FAIL') . "\n";

my $echo = send_recv({
    jsonrpc => "2.0", id => 5, method => "tools/call",
    params => {
        name => "echo",
        arguments => { msg => "test 123" },
    },
});
print "Echo result: " . ($echo->{result}{content}[0]{text} // 'FAIL') . "\n";

close($hub);