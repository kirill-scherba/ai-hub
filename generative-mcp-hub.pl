#!/usr/bin/env perl
# =============================================================================
# generative-mcp-hub — MCP server for generative AI tool creation
#
# Repository: github.com/kirill-scherba/ai-hub
#
# What is this?
# An MCP server that lets AI assistants GENERATE new MCP tools at runtime,
# execute them in a Safe sandbox, and share them with other AIs.
#
# Features:
#   - tool_generate: Create a new MCP tool by providing name, schema, and
#     Perl code. Code is compiled in Safe sandbox and instantly available.
#   - tool_list: List all registered tools (built-in + generated).
#   - tool_export: Export a tool definition as JSON (for sharing/saving).
#   - tool_import: Import a tool from JSON.
#   - tool_remove: Remove a generated tool.
#   - Dynamic execution: Generated tools are called via tools/call just like
#     built-in tools.
#
# Why Perl? Because Safe->new() is built into Perl's core since 1994.
# No Python, JavaScript, or Lua offers a built-in sandbox.
#
# MCP protocol: JSON-RPC 2.0 over stdin/stdout
# =============================================================================

use strict;
use warnings;
use utf8;
use JSON;
use JSON::PP;
use Safe;
use POSIX qw(strftime);

use English '-no_match_vars';

# ---------------------------------------------------------------------------
# UTF-8 encoding
# ---------------------------------------------------------------------------
binmode(STDIN,  ":utf8");
binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

# ---------------------------------------------------------------------------
# Logging (to stderr — stdout is reserved for JSON-RPC protocol)
# ---------------------------------------------------------------------------
my $DEBUG = $ENV{AI_HUB_DEBUG} // 0;
my $HUB_URL = '';

# Parse command line arguments
sub parse_args {
    for my $i (0 .. $#ARGV) {
        if ($ARGV[$i] eq '--hub-url' && $i + 1 < @ARGV) {
            $HUB_URL = $ARGV[$i + 1];
            $HUB_URL =~ s/\/$//;  # strip trailing slash
        }
    }
    # Fallback to env
    if (!$HUB_URL && $ENV{AI_HUB_SERVER_URL}) {
        $HUB_URL = $ENV{AI_HUB_SERVER_URL};
        $HUB_URL =~ s/\/$//;
    }
}
parse_args();

sub log_message {
    my ($level, $message) = @_;
    return if $level eq 'DEBUG' && !$DEBUG;
    my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
    print STDERR "[$timestamp] [$level] $message\n";
    STDERR->flush();
}

# ---------------------------------------------------------------------------
# JSON-RPC helpers
# ---------------------------------------------------------------------------
my $json = JSON->new->allow_nonref;

sub respond {
    my ($id, $result) = @_;
    my $response = { jsonrpc => "2.0", id => $id, result => $result };
    print $json->encode($response) . "\n";
    STDOUT->flush();
}

sub respond_error {
    my ($id, $code, $message, $data) = @_;
    my $error = { code => $code, message => $message };
    $error->{data} = $data if defined $data;
    my $response = { jsonrpc => "2.0", id => $id, error => $error };
    print $json->encode($response) . "\n";
    STDOUT->flush();
}

sub send_notification {
    my ($method, $params) = @_;
    my $notification = { jsonrpc => "2.0", method => $method };
    $notification->{params} = $params if defined $params;
    print $json->encode($notification) . "\n";
    STDOUT->flush();
    log_message("INFO", "Notification: $method");
}

# Pre-create a JSON::PP decoder object — created before any sandbox exists.
# This is a blessed reference, not a class method call, so it survives
# the @JSON::ISA corruption that Safe sandbox causes.
# NOTE: must be a package global (not my) so _safe_http_get_json can see it
# when called from inside the Safe sandbox, since Safe only shares sub names,
# not lexical variables.
our $json_pp_decoder = JSON::PP->new->allow_nonref;

# ---------------------------------------------------------------------------
# Shared HTTP GET functions for Safe sandbox
#
# _safe_http_get:  raw HTTP GET, returns { success, status, content }
# _safe_http_get_json: HTTP GET + JSON decode, returns { success, status, data }
#
# JSON decoding happens HERE in main:: namespace where JSON::PP works.
# The sandbox code just calls _safe_http_get_json and gets a Perl hashref.
# ---------------------------------------------------------------------------

sub _safe_http_get {
    my ($url) = @_;
    print STDERR "[_safe_http_get] URL=$url\n";
    my ($content, $status, $http_code);
    # Use a temp file for raw bytes (avoids Perl IO layer UTF-8 corruption),
    # and backticks to capture curl's -w http_code output on stdout.
    my $tmpfile = "/tmp/ai_hub_curl_$$.bin";
    my $http_code_str = `curl -sS --max-time 10 -o "$tmpfile" -w "%{http_code}" "$url" 2>/dev/null`;
    if (defined $http_code_str && length($http_code_str) > 0 && $http_code_str =~ /^\d+$/) {
        $http_code = $http_code_str;
        $status    = $http_code + 0;
        open(my $fh, '<:raw', $tmpfile) or die "Cannot read tmpfile: $!";
        local $/;
        $content = <$fh>;
        close $fh;
        unlink $tmpfile;
        utf8::decode($content);
        print STDERR "[_safe_http_get] status=$status content_len=" . length($content) . " http_code=$http_code\n";
    } else {
        print STDERR "[_safe_http_get] curl failed or no http_code: '$http_code_str'\n";
        $content = '';
        $status  = 0;
        unlink $tmpfile if -f $tmpfile;
    }
    return {
        success => ($status >= 200 && $status < 300) ? 1 : 0,
        status  => $status,
        reason  => $status >= 200 && $status < 300 ? 'OK' : 'curl error',
        content => $content,
    };
}

# URI-escape a UTF-8 string by percent-encoding non-ASCII bytes.
# Uses simple regex without external modules — safe for sandbox usage.
sub _uri_escape_utf8 {
    my ($str) = @_;
    # Split into individual characters, convert each to UTF-8 bytes,
    # then percent-encode each byte. Use pack with U0C* for UTF-8 byte seq.
    my $escaped = '';
    for my $ch (split //, $str) {
        my $ord = ord($ch);
        if ($ord < 0x80) {
            # ASCII — percent-encode if not unreserved
            if ($ch =~ /^[a-zA-Z0-9_.~-]$/) {
                $escaped .= $ch;
            } else {
                $escaped .= sprintf('%%%02X', $ord);
            }
        } else {
            # Multi-byte UTF-8 — pack as UTF-8 byte sequence
            my $bytes;
            if ($ord < 0x800) {
                $bytes = pack('C2', (0xC0 | ($ord >> 6)), (0x80 | ($ord & 0x3F)));
            } elsif ($ord < 0x10000) {
                $bytes = pack('C3', (0xE0 | ($ord >> 12)), (0x80 | (($ord >> 6) & 0x3F)), (0x80 | ($ord & 0x3F)));
            } else {
                $bytes = pack('C4', (0xF0 | ($ord >> 18)), (0x80 | (($ord >> 12) & 0x3F)), (0x80 | (($ord >> 6) & 0x3F)), (0x80 | ($ord & 0x3F)));
            }
            $escaped .= join('', map { sprintf('%%%02X', $_) } unpack('C*', $bytes));
        }
    }
    return $escaped;
}

sub _safe_http_get_json {
    my ($url) = @_;
    print STDERR "[_safe_http_get_json] URL=$url\n";
    my $raw = _safe_http_get($url);
    return $raw unless $raw->{success};
    # Use the pre-created $main::json_pp_decoder blessed reference.
    # Method call on a blessed reference does NOT go through @ISA,
    # so Safe sandbox @JSON::PP::ISA corruption does not affect it.
    # $main::json_pp_decoder is 'our' variable, visible from main::
    # even when _safe_http_get_json is called from inside Safe sandbox.
    my $data = eval { $main::json_pp_decoder->decode($raw->{content}) };
    if ($@) {
        print STDERR "[_safe_http_get_json] JSON decode error: $@\n";
        return { success => 0, status => $raw->{status}, reason => "JSON decode error: $@" };
    }
    print STDERR "[_safe_http_get_json] decoded OK, type=" . ref($data) . "\n";
    return { success => 1, status => $raw->{status}, data => $data };
}

# Tool registry — stores generated tools
my %tool_registry;  # name => { name, description, inputSchema, code, compiled, source }

# ---------------------------------------------------------------------------
# Persistence — save/load generated tools to/from JSON file
# ---------------------------------------------------------------------------
use FindBin;
my $TOOLS_FILE = "$FindBin::Bin/tools.json";

sub save_tools {
    my @tools;
    for my $name (sort keys %tool_registry) {
        my $t = $tool_registry{$name};
        push @tools, {
            name        => $t->{name},
            description => $t->{description},
            inputSchema => $t->{inputSchema},
            code        => $t->{code},
            source      => $t->{source},
            created_at  => $t->{created_at},
        };
    }
    my $content = eval { $json->pretty->encode(\@tools) };
    return unless defined $content;
    open(my $fh, '>:utf8', $TOOLS_FILE) or return;
    print $fh $content;
    close $fh;
    log_message("INFO", "Saved " . scalar(@tools) . " tools to $TOOLS_FILE");
}

sub load_tools {
    return unless -f $TOOLS_FILE;
    open(my $fh, '<:utf8', $TOOLS_FILE) or return;
    local $/;
    my $content = <$fh>;
    close $fh;
    my $tools = eval { $json->decode($content) };
    return unless ref $tools eq 'ARRAY';
    my $loaded = 0;
    for my $t (@$tools) {
        next unless $t->{name} && $t->{code};
        eval {
            my $compiled = compile_in_safe($t->{code});
            $tool_registry{$t->{name}} = {
                name        => $t->{name},
                description => $t->{description} // "Imported tool",
                inputSchema => $t->{inputSchema} // { type => "object", properties => {} },
                code        => $t->{code},
                compiled    => $compiled,
                source      => $t->{source} // "persisted",
                created_at  => $t->{created_at} // strftime("%Y-%m-%d %H:%M:%S", localtime),
            };
            $loaded++;
        };
    }
    log_message("INFO", "Loaded $loaded tools from $TOOLS_FILE");
}

# Safe-whitelisted modules
my %safe_modules = (
    'MIME::Base64' => 1,
    'Digest::MD5'  => 1,
    'URI::Escape'  => 1,
    'Scalar::Util' => 1,
    'Cwd'          => 1,
    'Time::Piece'  => 1,
    'JSON::PP'     => 1,
    'Encode'       => 1,
);

# ---------------------------------------------------------------------------
# Safe sandbox compiler — compiles Perl code into a Safe sandbox
# ---------------------------------------------------------------------------
sub compile_in_safe {
    my ($code) = @_;

    my $safe = Safe->new();

    # Load and share whitelisted modules (those with 'use' in the code)
    my $code_copy = $code;
    while ($code_copy =~ s/^\s*use\s+([\w::]+)\s*;//m) {
        my $module_name = $1;
        die "Module '$module_name' is not allowed in Safe sandbox."
            unless $safe_modules{$module_name};
        eval "require $module_name; 1" or die "Cannot load module '$module_name': $@";
        no strict 'refs';
        my @symbols = keys %{$module_name . '::'};
        $safe->share_from($module_name, \@symbols);
        log_message("DEBUG", "Loaded module '$module_name' for safe eval.");
    }

    # Strip 'use' statements from the actual code (already loaded)
    $code_copy =~ s/^\s*use\s+[\w:]+\s*;//gm;

    # Share HTTP functions and URI escape helper.
    # _safe_http_get_json does JSON::PP::decode_json HERE in main:: namespace,
    # not inside the sandbox — so JSON::PP doesn't need to be shared.
    $safe->share(qw(&_safe_http_get &_safe_http_get_json &_uri_escape_utf8));

    # Compile the tool function
    my $compiled = $safe->reval("sub { my \$args = shift; $code_copy }");
    die "Perl Compile Error: $@" if $@;

    return $compiled;
}

# ---------------------------------------------------------------------------
# Built-in tool: tool_generate
# ---------------------------------------------------------------------------
sub tool_generate {
    my ($args) = @_;
    my $name        = $args->{name}        or die "Missing required parameter: 'name'";
    my $description = $args->{description} // "AI-generated tool";
    my $inputSchema = $args->{inputSchema} // { type => "object", properties => {} };
    my $code        = $args->{code}        or die "Missing required parameter: 'code'";
    my $source      = $args->{source}      // "runtime";  # runtime, import, etc.

    # Validate name (alphanumeric, underscores, colons)
    die "Invalid tool name '$name'. Use alphanumeric, underscores, or colons."
        unless $name =~ /^[a-zA-Z_][\w:]*$/;

    # Prevent overwriting built-in tools
    my @builtin = qw(tool_generate tool_list tool_export tool_import tool_remove hub_publish hub_search hub_pull hub_list);
    die "Cannot overwrite built-in tool '$name'." if grep { $_ eq $name } @builtin;

    # Compile the code in Safe sandbox
    my $compiled = compile_in_safe($code);

    # Register the tool
    $tool_registry{$name} = {
        name        => $name,
        description => $description,
        inputSchema => $inputSchema,
        code        => $code,
        compiled    => $compiled,
        source      => $source,
        created_at  => strftime("%Y-%m-%d %H:%M:%S", localtime),
    };

    # Save to persistent storage
    save_tools();

    log_message("INFO", "Generated tool: $name");
    return { status => "success", data => "Tool '$name' generated and registered." };
}

# ---------------------------------------------------------------------------
# Built-in tool: tool_list
# ---------------------------------------------------------------------------
sub tool_list {
    my $args = shift || {};
    my $include_code = $args->{include_code} // 0;

    my @builtin_tools = (
        {
            name        => "tool_generate",
            description => "Generate a new MCP tool. Provide name, description, inputSchema (JSON Schema), and Perl code. The code runs in a Safe sandbox.",
            inputSchema => {
                type => "object",
                properties => {
                    name => {
                        type => "string",
                        description => "Tool name (alphanumeric, underscores, colons).",
                    },
                    description => {
                        type => "string",
                        description => "Human-readable description of the tool.",
                    },
                    inputSchema => {
                        type => "object",
                        description => "JSON Schema for tool parameters.",
                    },
                    code => {
                        type => "string",
                        description => "Perl code that receives \$args hashref and returns a hashref result.",
                    },
                    source => {
                        type => "string",
                        description => "Source label (runtime, import, etc.). Optional.",
                    },
                },
                required => ["name", "code"],
            },
        },
        {
            name        => "tool_list",
            description => "List all registered tools (built-in + generated). Optionally include their code.",
            inputSchema => {
                type => "object",
                properties => {
                    include_code => {
                        type => "boolean",
                        description => "If true, include Perl code in the response.",
                    },
                },
            },
        },
        {
            name        => "tool_export",
            description => "Export a generated tool as JSON for sharing or saving.",
            inputSchema => {
                type => "object",
                properties => {
                    name => {
                        type => "string",
                        description => "Name of the tool to export.",
                    },
                },
                required => ["name"],
            },
        },
        {
            name        => "tool_import",
            description => "Import a tool from a JSON definition (previously exported).",
            inputSchema => {
                type => "object",
                properties => {
                    definition => {
                        type => "string",
                        description => "JSON string containing the tool definition.",
                    },
                },
                required => ["definition"],
            },
        },
        {
            name        => "tool_remove",
            description => "Remove a generated tool from the registry.",
            inputSchema => {
                type => "object",
                properties => {
                    name => {
                        type => "string",
                        description => "Name of the tool to remove.",
                    },
                },
                required => ["name"],
            },
        },
    );

    my @generated_tools;
    for my $name (sort keys %tool_registry) {
        my $t = $tool_registry{$name};
        my $entry = {
            name        => $t->{name},
            description => $t->{description},
            inputSchema => $t->{inputSchema},
            source      => $t->{source},
            created_at  => $t->{created_at},
        };
        $entry->{code} = $t->{code} if $include_code;
        push @generated_tools, $entry;
    }

    return {
        status  => "success",
        data    => {
            builtin   => \@builtin_tools,
            generated => \@generated_tools,
            count     => scalar(keys %tool_registry) + scalar(@builtin_tools),
        },
    };
}

# ---------------------------------------------------------------------------
# Built-in tool: tool_export
# ---------------------------------------------------------------------------
sub tool_export {
    my ($args) = @_;
    my $name = $args->{name} or die "Missing required parameter: 'name'";

    my $tool = $tool_registry{$name};
    die "Tool '$name' not found." unless $tool;

    my $export = {
        name        => $tool->{name},
        description => $tool->{description},
        inputSchema => $tool->{inputSchema},
        code        => $tool->{code},
        created_at  => $tool->{created_at},
    };

    log_message("INFO", "Exported tool: $name");
    return { status => "success", data => $export };
}

# ---------------------------------------------------------------------------
# Built-in tool: tool_import
# ---------------------------------------------------------------------------
sub tool_import {
    my ($args) = @_;
    my $definition_json = $args->{definition} or die "Missing required parameter: 'definition'";

    my $definition = eval { $json->decode($definition_json) };
    die "Invalid JSON definition: $@" if $@;
    die "Definition must be a hashref." unless ref $definition eq 'HASH';
    die "Definition missing 'name'." unless $definition->{name};
    die "Definition missing 'code'." unless $definition->{code};

    # Add source = 'import'
    $definition->{source} = 'import';

    # Use tool_generate logic to register
    return tool_generate($definition);
}

# ---------------------------------------------------------------------------
# Built-in tool: tool_remove
# ---------------------------------------------------------------------------
sub tool_remove {
    my ($args) = @_;
    my $name = $args->{name} or die "Missing required parameter: 'name'";

    die "Tool '$name' not found." unless exists $tool_registry{$name};
    delete $tool_registry{$name};

    # Save to persistent storage after removal
    save_tools();

    log_message("INFO", "Removed tool: $name");
    return { status => "success", data => "Tool '$name' removed." };
}

# ---------------------------------------------------------------------------
# Execute a generated tool in Safe sandbox
# ---------------------------------------------------------------------------
sub execute_generated_tool {
    my ($name, $args) = @_;

    my $tool = $tool_registry{$name};
    die "Tool '$name' not found." unless $tool;

    my $compiled = $tool->{compiled};

    # Execute in sandbox (Safe sandbox corrupts UTF-8 in the return value)
    my $result = eval { $compiled->($args) };
    if ($@) {
        log_message("ERROR", "Runtime error in tool '$name': $@");
        return { status => "error", data => "Runtime error: $@" };
    }

    # If the tool returned _raw_b64, decode base64 OUTSIDE sandbox
    # (base64 is ASCII-safe and survives sandbox UTF-8 corruption),
    # then decode JSON from the recovered bytes.
    my $raw_decode_result;
    if (defined $result && ref $result eq 'HASH' && exists $result->{_raw_b64}) {
        require MIME::Base64;
        my $b64 = delete $result->{_raw_b64};
        my $original_text = delete $result->{_original_text};
        my $src = delete $result->{_source};
        my $tgt = delete $result->{_target};
        my $url = delete $result->{_url};
        # Decode base64 (get raw bytes), convert to Perl UTF-8
        my $raw = MIME::Base64::decode_base64($b64);
        utf8::decode($raw);
        my $decoded = eval { $json_pp_decoder->decode($raw) };
        if ($decoded && ref $decoded eq 'HASH') {
            my $translated = $decoded->{responseData}{translatedText} // '';
            my $detected   = $decoded->{responseData}{detectedLanguage} // $src;
            my $match      = ($decoded->{responseData}{match} // 0) + 0;
            $raw_decode_result = {
                original_text   => $original_text,
                translated_text => $translated,
                source_lang     => $detected,
                target_lang     => $tgt,
                match_quality   => $match,
                _decoded_outside_sandbox => 1,
            };
        } else {
            $raw_decode_result = {
                original_text   => $original_text,
                source_lang     => $src,
                target_lang     => $tgt,
                _decode_error   => $@ // 'unknown',
                _url            => $url,
            };
        }
        # Replace result with decoded data for UTF-8 fixing
        $result = $raw_decode_result;
    }

    # Fix UTF-8 corruption: Safe sandbox strips the UTF-8 flag from strings.
    require Encode;
    my $fix_utf8;
    $fix_utf8 = sub {
        my ($val) = @_;
        if (ref $val eq 'HASH') {
            my %fixed;
            for my $k (keys %$val) {
                $fixed{$fix_utf8->($k)} = $fix_utf8->($val->{$k});
            }
            return \%fixed;
        } elsif (ref $val eq 'ARRAY') {
            return [ map { $fix_utf8->($_) } @$val ];
        } elsif (!ref $val && defined $val && length($val) > 0) {
            if ($val =~ /[\x80-\xFF]/ && !Encode::is_utf8($val)) {
                eval {
                    my $bytes = Encode::encode('latin1', $val);
                    $val = Encode::decode('utf-8', $bytes);
                };
            }
            return $val;
        }
        return $val;
    };
    if (defined $result && ref $result) {
        $result = $fix_utf8->($result);
    }

    # Debug: log result type and content
    log_message("DEBUG", "Sandbox result type=" . (defined($result) ? ref($result) : 'undef') . " content=" . (defined($result) ? $json->encode($result) : 'undef'));

    log_message("INFO", "Executed generated tool: $name");
    return { status => "success", data => $result };
}

# ---------------------------------------------------------------------------
# Hub HTTP helpers — communicate with Hub Server via REST API
# ---------------------------------------------------------------------------

sub hub_http_get {
    my ($path) = @_;
    return _safe_http_get("$HUB_URL$path");
}

sub hub_http_post {
    my ($path, $data) = @_;
    my $body = $json->encode($data);
    my ($content, $status);
    if (open(my $fh, '-|', 'curl', '-sS', '--max-time', '10',
             '-X', 'POST', '-H', 'Content-Type: application/json',
             '-d', $body, '-o', '-', '-w', "\n%{http_code}\n",
             "$HUB_URL$path")) {
        local $/;
        my $all = <$fh>;
        close $fh;
        utf8::decode($all);
        my @parts = split /\n/, $all;
        my $http_code = pop @parts;
        $content = join("\n", @parts);
        $status  = $http_code + 0;
    } else {
        $content = '';
        $status  = 0;
    }
    return {
        success => ($status >= 200 && $status < 300) ? 1 : 0,
        status  => $status,
        reason  => $status >= 200 && $status < 300 ? 'OK' : 'curl error',
        content => $content,
    };
}

sub hub_is_connected {
    return $HUB_URL ne '' ? 1 : 0;
}

# Check hub connectivity at startup
sub hub_check {
    return unless hub_is_connected();
    my $resp = hub_http_get('/tools?prefix=');
    if ($resp->{success}) {
        log_message("INFO", "Connected to Hub Server at $HUB_URL");
    } else {
        log_message("WARN", "Cannot connect to Hub Server at $HUB_URL (status=$resp->{status}) — hub tools will return errors");
    }
}

# ---------------------------------------------------------------------------
# Hub built-in tools
# ---------------------------------------------------------------------------

# hub_publish: Publish a local tool to the Hub Server
sub hub_publish {
    my ($args) = @_;
    defined $HUB_URL && $HUB_URL ne '' or die "Hub Server not configured. Use --hub-url <URL> or set AI_HUB_SERVER_URL env var.";

    my $name = $args->{name} or die "Missing required parameter: 'name'";
    exists $tool_registry{$name} or die "Tool '$name' not found in local registry.";

    # Export tool definition
    my $export = tool_export({ name => $name });
    my $definition = $export->{data};

    # POST to hub
    my $resp = hub_http_post('/tools', $definition);
    $resp->{success} or die "Hub publish failed: $resp->{reason} (HTTP $resp->{status})";

    log_message("INFO", "Published tool '$name' to Hub at $HUB_URL");
    return { status => "success", data => "Tool '$name' published to Hub." };
}

# hub_search: Semantic search for tools on the Hub
sub hub_search {
    my ($args) = @_;
    defined $HUB_URL && $HUB_URL ne '' or die "Hub Server not configured. Use --hub-url <URL> or set AI_HUB_SERVER_URL env var.";

    my $query = $args->{query} or die "Missing required parameter: 'query'";
    my $limit = $args->{limit} // 10;

    my $path = "/search?q=" . uri_esc($query) . "&limit=$limit";
    my $resp = hub_http_get($path);
    $resp->{success} or die "Hub search failed: $resp->{reason} (HTTP $resp->{status})";

    my $results = $json->decode($resp->{content});
    log_message("INFO", "Hub search for '$query': " . scalar(@$results) . " results");
    return { status => "success", data => $results };
}

# hub_pull: Download a tool from Hub and install locally
sub hub_pull {
    my ($args) = @_;
    defined $HUB_URL && $HUB_URL ne '' or die "Hub Server not configured. Use --hub-url <URL> or set AI_HUB_SERVER_URL env var.";

    my $name = $args->{name} or die "Missing required parameter: 'name'";

    my $path = "/tools/" . uri_esc($name);
    my $resp = hub_http_get($path);
    $resp->{success} or die "Hub pull failed: $resp->{reason} (HTTP $resp->{status})";

    my $definition = $resp->{content};

    # Import locally
    my $result = tool_import({ definition => $definition });
    log_message("INFO", "Pulled tool '$name' from Hub at $HUB_URL");
    return { status => "success", data => "Tool '$name' pulled from Hub and installed." };
}

# hub_list: List tools available on the Hub
sub hub_list {
    my ($args) = @_;
    defined $HUB_URL && $HUB_URL ne '' or die "Hub Server not configured. Use --hub-url <URL> or set AI_HUB_SERVER_URL env var.";

    my $prefix = $args->{prefix} // '';

    my $path = "/tools?prefix=" . uri_esc($prefix);
    my $resp = hub_http_get($path);
    $resp->{success} or die "Hub list failed: $resp->{reason} (HTTP $resp->{status})";

    my $tools = $json->decode($resp->{content});
    log_message("INFO", "Hub list: " . scalar(@$tools) . " tools");
    return { status => "success", data => $tools };
}

# URI escape helper
sub uri_esc {
    my ($s) = @_;
    $s =~ s/([^a-zA-Z0-9_.~-])/sprintf('%%%02X', ord($1))/ge;
    return $s;
}

# ---------------------------------------------------------------------------
# Main dispatcher for built-in tools
# ---------------------------------------------------------------------------
sub execute_builtin {
    my ($name, $args) = @_;

    if ($name eq 'tool_generate') {
        return tool_generate($args);
    }
    elsif ($name eq 'tool_list') {
        return tool_list($args);
    }
    elsif ($name eq 'tool_export') {
        return tool_export($args);
    }
    elsif ($name eq 'tool_import') {
        return tool_import($args);
    }
    elsif ($name eq 'tool_remove') {
        return tool_remove($args);
    }
    elsif ($name eq 'hub_publish') {
        return hub_publish($args);
    }
    elsif ($name eq 'hub_search') {
        return hub_search($args);
    }
    elsif ($name eq 'hub_pull') {
        return hub_pull($args);
    }
    elsif ($name eq 'hub_list') {
        return hub_list($args);
    }

    die "Unknown built-in tool: '$name'";
}

# ---------------------------------------------------------------------------
# Get combined tool definitions for tools/list
# ---------------------------------------------------------------------------
sub get_all_tool_definitions {
    my @tools;

    # Built-in tools
    push @tools, {
        name        => "tool_generate",
        description => "Generate a new MCP tool. Provide name, description, inputSchema (JSON Schema), and Perl code. The code runs in a Safe sandbox.",
        inputSchema => {
            type => "object",
            properties => {
                name => {
                    type => "string",
                    description => "Tool name (alphanumeric, underscores, colons).",
                },
                description => {
                    type => "string",
                    description => "Human-readable description of the tool.",
                },
                inputSchema => {
                    type => "object",
                    description => "JSON Schema for tool parameters.",
                },
                code => {
                    type => "string",
                    description => "Perl code that receives \$args hashref and returns a hashref result.",
                },
                source => {
                    type => "string",
                    description => "Source label (runtime, import, etc.). Optional.",
                },
            },
            required => ["name", "code"],
        },
    };
    push @tools, {
        name        => "tool_list",
        description => "List all registered tools (built-in + generated). Optionally include their code.",
        inputSchema => {
            type => "object",
            properties => {
                include_code => {
                    type => "boolean",
                    description => "If true, include Perl code in the response.",
                },
            },
        },
    };
    push @tools, {
        name        => "tool_export",
        description => "Export a generated tool as JSON for sharing or saving.",
        inputSchema => {
            type => "object",
            properties => {
                name => {
                    type => "string",
                    description => "Name of the tool to export.",
                },
            },
            required => ["name"],
        },
    };
    push @tools, {
        name        => "tool_import",
        description => "Import a tool from a JSON definition (previously exported).",
        inputSchema => {
            type => "object",
            properties => {
                definition => {
                    type => "string",
                    description => "JSON string containing the tool definition.",
                },
            },
            required => ["definition"],
        },
    };
    push @tools, {
        name        => "tool_remove",
        description => "Remove a generated tool from the registry.",
        inputSchema => {
            type => "object",
            properties => {
                name => {
                    type => "string",
                    description => "Name of the tool to remove.",
                },
            },
            required => ["name"],
        },
    };
    push @tools, {
        name        => "hub_publish",
        description => "Publish a local generated tool to the Hub Server for sharing with other MCP instances.",
        inputSchema => {
            type => "object",
            properties => {
                name => {
                    type => "string",
                    description => "Name of the local tool to publish.",
                },
            },
            required => ["name"],
        },
    };
    push @tools, {
        name        => "hub_search",
        description => "Semantic search for tools on the Hub Server.",
        inputSchema => {
            type => "object",
            properties => {
                query => {
                    type => "string",
                    description => "Search query (natural language).",
                },
                limit => {
                    type => "number",
                    description => "Maximum number of results (default: 10).",
                },
            },
            required => ["query"],
        },
    };
    push @tools, {
        name        => "hub_pull",
        description => "Download a tool from the Hub Server and install it locally.",
        inputSchema => {
            type => "object",
            properties => {
                name => {
                    type => "string",
                    description => "Name of the tool to pull from Hub.",
                },
            },
            required => ["name"],
        },
    };
    push @tools, {
        name        => "hub_list",
        description => "List tools available on the Hub Server.",
        inputSchema => {
            type => "object",
            properties => {
                prefix => {
                    type => "string",
                    description => "Optional prefix to filter tool names.",
                },
            },
        },
    };

    # Generated tools
    for my $name (sort keys %tool_registry) {
        my $t = $tool_registry{$name};
        push @tools, {
            name        => $t->{name},
            description => $t->{description},
            inputSchema => $t->{inputSchema},
        };
    }

    return \@tools;
}

# ===========================================================================
# MCP Main Loop — Infinite loop processing JSON-RPC requests from stdin
# ===========================================================================

log_message("INFO", "generative-mcp-hub server started");

# Load persisted tools from disk
load_tools();

# Check hub connectivity
hub_check();

# Notify the client that we are ready
send_notification("initialized");

LINE: while (my $line = <STDIN>) {
    chomp $line;
    next LINE unless $line && $line =~ /\S/;

    log_message("DEBUG", "Received: $line");

    my $msg = eval { $json->decode($line) };
    if ($@ || !$msg) {
        log_message("ERROR", "Invalid JSON-RPC message: $@");
        next LINE;
    }

    my $id     = $msg->{id};
    my $method = $msg->{method} // '';
    my $params = $msg->{params} // {};

    # Handle notifications (no id)
    if (!defined $id) {
        log_message("INFO", "Received notification: $method");
        next LINE;
    }

    if ($method eq 'initialize') {
        respond($id, {
            protocolVersion => '2024-11-05',
            capabilities    => { tools => {} },
            serverInfo      => {
                name    => 'generative-mcp-hub',
                version => '0.1.0',
            },
        });
        log_message("INFO", "Initialized");
    }
    elsif ($method eq 'ping') {
        respond($id, {});
    }
    elsif ($method eq 'tools/list') {
        respond($id, {
            tools => get_all_tool_definitions(),
        });
        log_message("INFO", "Sent tool list (" . scalar(keys %tool_registry) . " generated)");
    }
    elsif ($method eq 'tools/call') {
        my $tool_name  = $params->{name} // '';
        my $tool_args  = $params->{arguments} // {};

        log_message("INFO", "Executing tool: $tool_name");

        eval {
            my $result;
            my @builtin = qw(tool_generate tool_list tool_export tool_import tool_remove hub_publish hub_search hub_pull hub_list);
            if (grep { $_ eq $tool_name } @builtin) {
                $result = execute_builtin($tool_name, $tool_args);
            }
            elsif (exists $tool_registry{$tool_name}) {
                $result = execute_generated_tool($tool_name, $tool_args);
            }
            else {
                die "Method not found: tool '$tool_name' not found";
            }

            log_message("INFO", "Tool execution successful: $tool_name");
            respond($id, {
                content => [
                    {
                        type => "text",
                        text => $json->encode($result),
                    },
                ],
            });
        };
        if ($@) {
            my $error_msg = $@;
            chomp $error_msg;
            log_message("ERROR", "Tool execution error: $error_msg");
            respond_error($id, -32603, "Internal error: $error_msg");
        }
    }
    else {
        log_message("WARN", "Unknown method: $method");
        respond_error($id, -32601, "Method not found: $method");
    }
}

# Cleanup
log_message("INFO", "generative-mcp-hub server stopped");