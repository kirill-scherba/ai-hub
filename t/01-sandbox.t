#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 11;

# Test the Safe sandbox in isolation
# Load the main module functions directly
require './generative-mcp-hub.pl';

# Test 1: Successful compilation of safe code
my $code = 'return { result => $args->{x} + $args->{y} };';
my $compiled;
eval {
    $compiled = compile_in_safe($code);
};
ok(!$@, 'Safe code compiles successfully') or diag("Error: $@");
ok(defined $compiled, 'Compiled result is defined');

# Test 2: Execute the compiled code
my $result = $compiled->({ x => 10, y => 20 });
is(ref $result, 'HASH', 'Result is a hashref');
is($result->{result}, 30, 'Addition works correctly');

# Test 3: Blocked — system() call
my $bad_code_system = 'system("echo hacked"); return { ok => 1 };';
eval {
    compile_in_safe($bad_code_system);
};
ok($@, 'system() is blocked') or diag("system() was NOT blocked! Security issue!");

# Test 4: Blocked — exec() call
my $bad_code_exec = 'exec("rm -rf /"); return { ok => 1 };';
eval {
    compile_in_safe($bad_code_exec);
};
ok($@, 'exec() is blocked') or diag("exec() was NOT blocked! Security issue!");

# Test 5: Blocked — backtick
my $bad_code_tick = 'my $out = `id`; return { ok => 1 };';
eval {
    compile_in_safe($bad_code_tick);
};
ok($@, 'backtick is blocked') or diag("backtick was NOT blocked! Security issue!");

# Test 6: Blocked — file open
my $bad_code_open = 'open(my $fh, ">", "/tmp/hacked"); return { ok => 1 };';
eval {
    compile_in_safe($bad_code_open);
};
ok($@, 'file open is blocked') or diag("file open was NOT blocked! Security issue!");

# Test 7: Blocked — unauthorized module
my $bad_code_module = 'use LWP::Simple; return { ok => 1 };';
eval {
    compile_in_safe($bad_code_module);
};
ok($@, 'unauthorized module is blocked') or diag("LWP::Simple was NOT blocked!");

# Test 8: Allowed — whitelisted module
my $good_code_module = 'use JSON::PP; my $j = JSON::PP->new; return { ok => 1 };';
eval {
    compile_in_safe($good_code_module);
};
ok(!$@, 'whitelisted module (JSON::PP) compiles') or diag("Error: $@");

# Test 9: Blocked — fork
my $bad_code_fork = 'my $pid = fork; return { ok => 1 };';
eval {
    compile_in_safe($bad_code_fork);
};
ok($@, 'fork is blocked') or diag("fork was NOT blocked! Security issue!");