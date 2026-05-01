#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 3;

use FindBin;
use lib $FindBin::Bin;
use lib "$FindBin::Bin/..";

require "$FindBin::Bin/../generative-mcp-hub.pl";

# Test 1: Valid tool name accepted
my $generate_args = {
    name        => "test_tool",
    description => "Test tool",
    inputSchema => { type => "object", properties => {} },
    source      => "test",
    code        => 'return { ok => 1 };',
};
eval {
    tool_generate($generate_args);
};
ok(!$@, 'Valid tool name accepted') or diag("Error: $@");

# Test 2: Invalid tool name — spaces rejected
my $bad_name = {
    name        => "bad name",
    description => "Bad",
    inputSchema => { type => "object", properties => {} },
    source      => "test",
    code        => 'return { ok => 1 };',
};
eval {
    tool_generate($bad_name);
};
ok($@, 'Invalid tool name (spaces) rejected');

# Test 3: Prevent overwriting built-in tools
my $overwrite = {
    name        => "tool_generate",
    description => "Overwrite attempt",
    inputSchema => { type => "object", properties => {} },
    source      => "test",
    code        => 'return { ok => 1 };',
};
eval {
    tool_generate($overwrite);
};
ok($@, 'Overwriting built-in tool is blocked') or diag("Built-in tool was overwritten!");