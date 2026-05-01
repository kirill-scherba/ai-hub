#!/usr/bin/env perl
# =============================================================================
# Test: Hub interaction (publish, search, pull, list)
#
# These tests require a running Hub Server.  If AI_HUB_SERVER_URL is not set
# and no --hub-url is passed, hub tests are skipped with "not applicable".
#
# You can start a test Hub Server with:
#
#   perl -e '
#       use strict; use warnings; use JSON;
#       my $json = JSON->new->allow_nonref;
#       my %tools;
#       while (<STDIN>) {
#           chomp; next unless /\S/;
#           my $msg = eval {$json->decode($_)};
#           next unless $msg && $msg->{method};
#           my $m = $msg->{method};
#           if ($m eq "initialize") {
#               print $json->encode({jsonrpc=>"2.0",id=>$msg->{id},result=>{protocolVersion=>"2024-11-05",capabilities=>{tools=>{}},serverInfo=>{name=>"test-hub",version=>"0.1.0"}}})."\n";
#           } elsif ($m eq "tools/list") {
#               print $json->encode({jsonrpc=>"2.0",id=>$msg->{id},result=>{tools=>[map {{name=>$_,description=>"Test tool $_",inputSchema=>{type=>"object",properties=>{}}}} keys %tools]}})."\n";
#           } elsif ($m eq "tools/call") {
#               my $tool = $msg->{params}{name};
#               print $json->encode({jsonrpc=>"2.0",id=>$msg->{id},result=>{content=>[{type=>"text",text=>qq({"status":"success","data":"ok"})}]}})."\n";
#           }
#       }
#   ' 2>/dev/null
#
# Then set AI_HUB_SERVER_URL=http://localhost:8484 and run the tests.
#
# Alternatively, set AI_HUB_SKIP_HUB=1 to skip all hub-* tests.
# =============================================================================

use strict;
use warnings;
use utf8;
use FindBin;
use lib $FindBin::Bin;
use lib "$FindBin::Bin/..";
use lib "$FindBin::Bin/..";
use Test::More;
use JSON;

# ---------------------------------------------------------------------------
# If AI_HUB_SKIP_HUB is set, skip all hub tests
# ---------------------------------------------------------------------------
if ($ENV{AI_HUB_SKIP_HUB}) {
    plan skip_all => "AI_HUB_SKIP_HUB is set — skipping hub interaction tests";
} else {
    plan 'no_plan';
}

# ---------------------------------------------------------------------------
# Load the main script (the caller guard prevents the MCP main loop from
# running, but all subs become available for direct calling)
# ---------------------------------------------------------------------------

BEGIN {
    require "$FindBin::Bin/../generative-mcp-hub.pl";
}

# ---------------------------------------------------------------------------
# Helper: Create and clean up test tools
# ---------------------------------------------------------------------------
sub create_test_tool {
    my ($name) = @_;
    return tool_generate({
        name        => $name,
        description => "Test tool for hub tests",
        inputSchema => { type => "object", properties => {} },
        source      => "test",
        code        => q|return { greeting => "Hello from " . $args->{name} // "world" };|,
    });
}

sub cleanup_tools {
    for my $name (keys %main::tool_registry) {
        eval { tool_remove({ name => $name }) };
    }
}

# ===========================================================================
# 1. Hub connectivity detection
# ===========================================================================

subtest "Hub connectivity detection" => sub {
    plan tests => 2;

    do {
        no strict 'refs';
        local ${"main::HUB_URL"} = '';
        ok(!hub_is_connected(), "hub_is_connected returns false when HUB_URL is empty");
    };

    do {
        no strict 'refs';
        local ${"main::HUB_URL"} = 'http://localhost:8484';
        ok(hub_is_connected(), "hub_is_connected returns true when HUB_URL is set");
    };
};

# ===========================================================================
# 2. Hub tools error handling (no hub configured)
# ===========================================================================

subtest "Hub tools error handling (no hub configured)" => sub {
    plan tests => 4;

    for my $test (
        [ "hub_list",  sub { hub_list({ prefix => '' }) } ],
        [ "hub_publish", sub { hub_publish({ name => 'test_tool' }) } ],
        [ "hub_search",  sub { hub_search({ query => 'test' }) } ],
        [ "hub_pull",    sub { hub_pull({ name => 'test_tool' }) } ],
    ) {
        my ($name, $code) = @$test;
        do {
            no strict 'refs';
            local ${"main::HUB_URL"} = '';
            my $caught;
            eval { $code->() };
            $caught = $@;
            ok($caught && $caught =~ /Hub Server not configured/, "$name dies with 'Hub Server not configured'");
        };
    }
};

# ===========================================================================
# 3. URI escape helper
# ===========================================================================

subtest "URI escape helper" => sub {
    plan tests => 3;

    is(uri_esc('hello world'), 'hello%20world', "uri_esc escapes spaces");
    is(uri_esc('Hello123'), 'Hello123', "uri_esc leaves alphanumerics intact");
    is(uri_esc('my_tool.test'), 'my_tool.test', "uri_esc handles underscores and dots");
};

# ===========================================================================
# 4. hub_http_get — error handling (unreachable host)
# ===========================================================================

subtest "hub_http_get error handling" => sub {
    plan tests => 1;

    do {
        no strict 'refs';
        local ${"main::HUB_URL"} = 'http://127.0.0.1:1';
        my $resp = hub_http_get('/tools');
        ok(!$resp->{success} && $resp->{status} == 0, "hub_http_get to unreachable host returns success=0");
    };
};

# ===========================================================================
# 5. hub_http_post — error handling
# ===========================================================================

subtest "hub_http_post error handling" => sub {
    plan tests => 1;

    do {
        no strict 'refs';
        local ${"main::HUB_URL"} = 'http://127.0.0.1:1';
        my $resp = hub_http_post('/tools', { name => 'ignored', code => 'return {};' });
        ok(!$resp->{success}, "hub_http_post to unreachable host returns success=0");
    };
};

# ===========================================================================
# 6. Live hub tests (only if hub is available)
# ===========================================================================

my $hub_available = 0;
my $test_url = $ENV{AI_HUB_TEST_URL} || $ENV{AI_HUB_SERVER_URL} || '';

if ($test_url) {
    do {
        no strict 'refs';
        local ${"main::HUB_URL"} = $test_url;
        ${"main::HUB_URL"} =~ s/\/$//;
        my $resp = hub_http_get('/tools?prefix=');
        $hub_available = $resp->{success} ? 1 : 0;
        if (!$hub_available) {
            diag("Hub server at $test_url not reachable — skipping live hub tests");
        }
    };
}

SKIP: {
    skip "Hub not available — set AI_HUB_SERVER_URL or AI_HUB_TEST_URL", 5 unless $hub_available;

    do {
        no strict 'refs';
        local ${"main::HUB_URL"} = $test_url;
        ${"main::HUB_URL"} =~ s/\/$//;

        cleanup_tools();

        # Create a test tool
        my $gen = create_test_tool('hub_test_sandwich');
        ok($gen->{status} eq 'success', "Created test tool 'hub_test_sandwich' for hub publish");

        # hub_publish
        my $pub = eval { hub_publish({ name => 'hub_test_sandwich' }) };
        if ($@) {
            fail("hub_publish: $@");
        } else {
            ok($pub->{status} eq 'success', "Published tool 'hub_test_sandwich' to hub");
        }

        # hub_list
        my $list = eval { hub_list({ prefix => '' }) };
        if ($@) {
            fail("hub_list: $@");
        } else {
            ok(ref $list->{data} eq 'ARRAY', "hub_list returned an array");
        }

        # hub_search
        my $search = eval { hub_search({ query => 'test', limit => 5 }) };
        if ($@) {
            fail("hub_search: $@");
        } else {
            ok(ref $search->{data} eq 'ARRAY', "hub_search returned an array");
        }

        # hub_pull
        my $pull = eval { hub_pull({ name => 'hub_test_sandwich' }) };
        if ($@) {
            fail("hub_pull: $@");
        } else {
            ok($pull->{status} eq 'success', "Pulled tool 'hub_test_sandwich' from hub");
            eval { tool_remove({ name => 'hub_test_sandwich' }) };
        }

        cleanup_tools();
    };
}

# Cleanup
cleanup_tools();

done_testing();
exit 0;