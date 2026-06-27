#!/usr/bin/env perl
# cloudflare-mcp.pl — MCP server for Cloudflare DNS management
# Provides tools to create and manage DNS records via Cloudflare API.
#
# Usage: standalone MCP server (started by opencode as external MCP)
#
# Env: CLOUDFLARE_API_TOKEN (required)

use strict;
use warnings;
use JSON::PP;

binmode(STDIN,  ":utf8");
binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

my $json = JSON::PP->new->allow_nonref;
my $API_TOKEN = $ENV{CLOUDFLARE_API_TOKEN} or die "CLOUDFLARE_API_TOKEN is required\n";
my $API_BASE  = "https://api.cloudflare.com/client/v4";

# ─── MCP Protocol ────────────────────────────────────────────────────────────

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

# ─── Cloudflare API ──────────────────────────────────────────────────────────

sub cf_api {
    my ($method, $path, $body) = @_;
    my $url = "$API_BASE$path";

    my $curl_cmd = "curl -s -X $method '$url'"
        . " -H 'Authorization: Bearer $API_TOKEN'"
        . " -H 'Content-Type: application/json'";

    if (defined $body) {
        my $tmp = "/tmp/cf_body_$$.json";
        open my $fh, '>', $tmp or die "Cannot write $tmp: $!";
        print $fh $json->encode($body);
        close $fh;
        $curl_cmd .= " -d \@$tmp";
    }

    my $result = `$curl_cmd`;
    die "Cloudflare API call failed: $?" if $? && !defined $result;
    return $json->decode($result);
}

sub cf_success {
    my ($method, $path, $body) = @_;
    my $resp = cf_api($method, $path, $body);
    die "Cloudflare API error: $resp->{errors}->[0]->{message}" unless $resp->{success};
    return $resp->{result};
}

# ─── Tool: List Zones ────────────────────────────────────────────────────────

sub handle_list_zones {
    my ($args) = @_;
    my $zones = cf_success("GET", "/zones");
    my @list = map { { name => $_->{name}, id => $_->{id}, status => $_->{status} } } @$zones;
    return { zones => \@list };
}

# ─── Tool: Create DNS Record ─────────────────────────────────────────────────

sub handle_create_dns {
    my ($args) = @_;

    my $zone_name = $args->{zone} || "bmat.uk";
    my $type      = uc($args->{type} || "A");
    my $name      = $args->{name} or die "name is required (e.g. 'newhost' for newhost.bmat.uk)";
    my $content   = $args->{content} or die "content is required (IP for A/AAAA, target for CNAME)";
    my $ttl       = $args->{ttl} || 120;
    my $proxied   = defined $args->{proxied} ? $args->{proxied} : JSON::PP::false;

    # Resolve zone ID from name
    my $zones = cf_success("GET", "/zones?name=$zone_name");
    die "Zone '$zone_name' not found" unless @$zones;
    my $zone_id = $zones->[0]->{id};

    my $record = cf_success("POST", "/zones/$zone_id/dns_records", {
        type    => $type,
        name    => $name,
        content => $content,
        ttl     => $ttl,
        proxied => $proxied,
    });

    return {
        success  => JSON::PP::true,
        zone     => $zone_name,
        type     => $record->{type},
        name     => $record->{name},
        content  => $record->{content},
        ttl      => $record->{ttl},
        proxied  => $record->{proxied} ? JSON::PP::true : JSON::PP::false,
        id       => $record->{id},
    };
}

# ─── Tool: Delete DNS Record ─────────────────────────────────────────────────

sub handle_delete_dns {
    my ($args) = @_;

    my $zone_name = $args->{zone} || "bmat.uk";
    my $record_id = $args->{id} or die "id is required (record ID from list or create)";

    my $zones = cf_success("GET", "/zones?name=$zone_name");
    die "Zone '$zone_name' not found" unless @$zones;
    my $zone_id = $zones->[0]->{id};

    cf_success("DELETE", "/zones/$zone_id/dns_records/$record_id");

    return { success => JSON::PP::true, deleted => $record_id };
}

# ─── Tool: List DNS Records ──────────────────────────────────────────────────

sub handle_list_dns {
    my ($args) = @_;

    my $zone_name = $args->{zone} || "bmat.uk";
    my $type      = $args->{type} || "";

    my $zones = cf_success("GET", "/zones?name=$zone_name");
    die "Zone '$zone_name' not found" unless @$zones;
    my $zone_id = $zones->[0]->{id};

    my $path = "/zones/$zone_id/dns_records";
    $path .= "?type=$type" if $type;

    my $records = cf_success("GET", $path);
    my @list = map {
        {
            id      => $_->{id},
            type    => $_->{type},
            name    => $_->{name},
            content => $_->{content},
            ttl     => $_->{ttl},
            proxied => $_->{proxied} ? JSON::PP::true : JSON::PP::false,
        }
    } @$records;

    return { zone => $zone_name, records => \@list };
}

# ─── Main Loop (JSON-RPC over stdin/stdout) ─────────────────────────────────

print STDERR "[cloudflare-mcp] server started\n";
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
            serverInfo      => { name => 'cloudflare-mcp', version => '0.1.0' },
        });
    }
    elsif ($method eq 'ping') {
        respond($id, {});
    }
    elsif ($method eq 'tools/list') {
        respond($id, {
            tools => [
                {
                    name        => "cloudflare_zone_list",
                    description => "List all Cloudflare zones (domains) accessible with the API token.",
                    inputSchema => { type => "object", properties => {} },
                },
                {
                    name        => "cloudflare_dns_create",
                    description => "Create a DNS record in a Cloudflare zone. Default zone is bmat.uk.",
                    inputSchema => {
                        type       => "object",
                        properties => {
                            zone    => { type => "string", description => "Zone/domain name (default: bmat.uk)" },
                            type    => { type => "string", description => "Record type: A, AAAA, CNAME (default: A)" },
                            name    => { type => "string", description => "Record name (e.g. 'newhost' for newhost.bmat.uk)" },
                            content => { type => "string", description => "Record value: IP for A/AAAA, target for CNAME" },
                            ttl     => { type => "integer", description => "TTL in seconds (default: 120, auto: 1)" },
                            proxied => { type => "boolean", description => "Proxy through Cloudflare (default: false)" },
                        },
                        required => ["name", "content"],
                    },
                },
                {
                    name        => "cloudflare_dns_delete",
                    description => "Delete a DNS record by ID.",
                    inputSchema => {
                        type       => "object",
                        properties => {
                            zone => { type => "string", description => "Zone/domain name (default: bmat.uk)" },
                            id   => { type => "string", description => "DNS record ID to delete" },
                        },
                        required => ["id"],
                    },
                },
                {
                    name        => "cloudflare_dns_list",
                    description => "List DNS records in a zone, optionally filtered by type.",
                    inputSchema => {
                        type       => "object",
                        properties => {
                            zone => { type => "string", description => "Zone/domain name (default: bmat.uk)" },
                            type => { type => "string", description => "Filter by record type: A, AAAA, CNAME, etc." },
                        },
                    },
                },
            ],
        });
    }
    elsif ($method eq 'tools/call') {
        my $tool_name = $msg->{params}{name} // '';
        my $tool_args = $msg->{params}{arguments} // {};

        my $result;
        if ($tool_name eq 'cloudflare_zone_list') {
            $result = handle_list_zones($tool_args);
        }
        elsif ($tool_name eq 'cloudflare_dns_create') {
            $result = eval { handle_create_dns($tool_args) };
            if ($@) {
                respond_error($id, -32603, chomp($@) ? "Error: $@" : "Error: $@");
                next LINE;
            }
        }
        elsif ($tool_name eq 'cloudflare_dns_delete') {
            $result = handle_delete_dns($tool_args);
        }
        elsif ($tool_name eq 'cloudflare_dns_list') {
            $result = handle_list_dns($tool_args);
        }
        else {
            respond_error($id, -32601, "Tool not found: $tool_name");
            next LINE;
        }

        $result = { status => "success", data => $result };
        respond($id, {
            content => [{ type => "text", text => $json->encode($result) }],
        });
    }
}
