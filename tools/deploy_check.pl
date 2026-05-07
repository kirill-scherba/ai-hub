#!/usr/bin/env perl
# deploy_check — standalone MCP tool: check deployment health of a URL
# Usage: perl deploy_check.pl <url>
# Returns JSON with compact table

use strict;
use warnings;
use JSON;

my $url = $ARGV[0] or die "Usage: $0 <url>\n";

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

# ---- SSL Expiry (via curl verbose, no openssl subprocess) ----
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
my ($robots_code, $robots_status);
{
    local $SIG{ALRM} = sub { die "timeout\n" };
    alarm 8;
    $robots_code = `curl -o /dev/null -s -w '%{http_code}' --connect-timeout 5 '$url/robots.txt' 2>&1`;
    alarm 0;
    $robots_status = ($robots_code eq '200') ? 'YES' : ($robots_code eq '404') ? 'no' : ($robots_code || 'ERR');
}

# ---- sitemap.xml ----
my ($sitemap_code, $sitemap_status);
{
    local $SIG{ALRM} = sub { die "timeout\n" };
    alarm 8;
    $sitemap_code = `curl -o /dev/null -s -w '%{http_code}' --connect-timeout 5 '$url/sitemap.xml' 2>&1`;
    alarm 0;
    $sitemap_status = ($sitemap_code eq '200') ? 'YES' : ($sitemap_code eq '404') ? 'no' : ($sitemap_code || 'ERR');
}

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

# Output JSON
my $json = JSON->new->canonical->pretty;
print $json->encode({
    url               => $url,
    http_status       => $http_code,
    response_time_ms  => $resp_time,
    ssl_expiry        => $ssl_expiry,
    robots_txt        => $robots_status,
    sitemap_xml       => $sitemap_status,
    table             => $table,
});