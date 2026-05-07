#!/usr/bin/env perl
# deploy-check-mcp — MCP server for deploy_check tool
# Checks: HTTP status, response time, SSL expiry, robots.txt, sitemap.xml

use strict;
use warnings;
use utf8;
use JSON;

binmode(STDIN,  ":utf8");
binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

my $json = JSON->new->allow_nonref;

sub respond {
    my ($id, $result) = @_;
    my $response = { jsonrpc => "2.0", id => $id, result => $result };
    print $json->encode($response) . "\n";
    STDOUT->flush();
}

sub respond_error {
    my ($id, $code, $message) = @_;
    my $response = { jsonrpc => "2.0", id => $id, error => { code => $code, message => $message } };
    print $json->encode($response) . "\n";
    STDOUT->flush();
}

sub do_deploy_check {
    my ($url) = @_;

    $url =~ s|/+$||;
    $url = 'https://' . $url unless $url =~ m{^https?://}i;

    my $host = $url;
    $host =~ s{^https?://}{}i;
    $host =~ s{/.*$}{};
    $host =~ s{:[0-9]+$}{};

    # ---- HTTP Status & Response Time ----
    my ($http_code, $resp_time);
    {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm 15;
        my $out = `curl -o /dev/null -s -w '%{http_code}:%{time_total}' --connect-timeout 10 '$url' 2>&1`;
        alarm 0;
        if ($out =~ /^(\d+):([\d.]+)/) {
            ($http_code, $resp_time) = ($1, sprintf('%.0f', $2 * 1000));
        } else {
            $http_code = 'ERR';
            $resp_time = '-';
        }
    }

    # ---- SSL Expiry ----
    my $ssl_expiry = '-';
    {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm 10;
        my $out = `curl -o /dev/null -s -v --connect-timeout 10 '$url' 2>&1`;
        alarm 0;
        if ($out =~ /expire date:\s*(.+)/i) {
            $ssl_expiry = $1;
        }
    }

    # ---- robots.txt ----
    my $robots_code;
    {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm 8;
        $robots_code = `curl -o /dev/null -s -w '%{http_code}' --connect-timeout 5 '$url/robots.txt' 2>&1`;
        alarm 0;
    }
    my $robots_status = ($robots_code eq '200') ? 'YES' : ($robots_code eq '404') ? 'no' : ($robots_code || 'ERR');

    # ---- sitemap.xml ----
    my $sitemap_code;
    {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm 8;
        $sitemap_code = `curl -o /dev/null -s -w '%{http_code}' --connect-timeout 5 '$url/sitemap.xml' 2>&1`;
        alarm 0;
    }
    my $sitemap_status = ($sitemap_code eq '200') ? 'YES' : ($sitemap_code eq '404') ? 'no' : ($sitemap_code || 'ERR');

    # ---- Format Table ----
    my $title = "Deploy Check: $url";
    my $sep   = '-' x (length($title) + 4);
    my $table = <<"TABLE";
$sep
| $title |
$sep
| Check           | Result
|-----------------|----------------------------------------------
| HTTP Status     | $http_code
| Response Time   | $resp_time ms
| SSL Expiry      | $ssl_expiry
| robots.txt      | $robots_status
| sitemap.xml     | $sitemap_status
$sep
TABLE

    return {
        url              => $url,
        http_status      => $http_code,
        response_time_ms => $resp_time . '',
        ssl_expiry       => $ssl_expiry,
        robots_txt       => $robots_status,
        sitemap_xml      => $sitemap_status,
        table            => $table,
    };
}

# ---- MCP Main Loop ----
print STDERR "[deploy-check-mcp] server started\n";
print $json->encode({ jsonrpc => "2.0", method => "initialized" }) . "\n";
STDOUT->flush();

LINE: while (my $line = <STDIN>) {
    chomp $line;
    next LINE unless $line && $line =~ /\S/;

    my $msg = eval { $json->decode($line) };
    if ($@ || !$msg) { next LINE }

    my $id     = $msg->{id};
    my $method = $msg->{method} // '';

    if (!defined $id) { next LINE }

    if ($method eq 'initialize') {
        respond($id, {
            protocolVersion => '2024-11-05',
            capabilities    => { tools => {} },
            serverInfo      => { name => 'deploy-check-mcp', version => '0.1.0' },
        });
    }
    elsif ($method eq 'ping') {
        respond($id, {});
    }
    elsif ($method eq 'tools/list') {
        respond($id, {
            tools => [{
                name        => "deploy_check",
                description => "Check deployment health of a URL: HTTP status code, response time, SSL certificate expiry, presence of robots.txt and sitemap.xml. Returns results in a compact formatted table.",
                inputSchema => {
                    type => "object",
                    properties => {
                        url => {
                            type        => "string",
                            description => "URL to check (e.g. https://example.com)",
                        },
                    },
                    required => ["url"],
                },
            }],
        });
    }
    elsif ($method eq 'tools/call') {
        my $tool_name = $msg->{params}{name} // '';
        my $tool_args = $msg->{params}{arguments} // {};

        if ($tool_name eq 'deploy_check') {
            my $url = $tool_args->{url} // '';
            if (!$url) {
                respond_error($id, -32602, "Missing required parameter: 'url'");
                next LINE;
            }
            my $result = do_deploy_check($url);
            $result = { status => "success", data => $result };
            respond($id, {
                content => [{ type => "text", text => $json->encode($result) }],
            });
        } else {
            respond_error($id, -32601, "Method not found: $tool_name");
        }
    }
    else {
        respond_error($id, -32601, "Method not found: $method");
    }
}

print STDERR "[deploy-check-mcp] server stopped\n";