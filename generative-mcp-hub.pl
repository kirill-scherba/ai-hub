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
my $json_pp_decoder = JSON::PP->new->allow_nonref;

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
    if (open(my $fh, '-|:utf8', 'curl', '-sS', '--max-time', '10',
             '-o', '-', '-w', "\n%{http_code}\n", $url)) {
        local $/;
        my $all = <$fh>;
        close $fh;
        my @parts = split /\n/, $all;
        $http_code = pop @parts;
        $content   = join("\n", @parts);
        $status    = $http_code + 0;
        print STDERR "[_safe_http_get] status=$status content_len=" . length($content) . " http_code=$http_code\n";
    } else {
        print STDERR "[_safe_http_get] open failed: $!\n";
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

sub _safe_http_get_json {
    my ($url) = @_;
    print STDERR "[_safe_http_get_json] URL=$url\n";
    my $raw = _safe_http_get($url);
    return $raw unless $raw->{success};
    # Use the pre-created JSON::PP decoder object (blessed before any sandbox
    # existed). An object METHOD call survives @JSON::ISA corruption that
    # Safe sandbox's reval causes on the JSON package.
    my $data = eval { $json_pp_decoder->decode($raw->{content}) };
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

    # Share HTTP functions.
    # _safe_http_get_json does JSON::PP::decode_json HERE in main:: namespace,
    # not inside the sandbox — so JSON::PP doesn't need to be shared.
    $safe->share(qw(&_safe_http_get &_safe_http_get_json));

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
    my @builtin = qw(tool_generate tool_list tool_export tool_import tool_remove weather exchange_rate);
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

    # Execute in sandbox
    my $result = eval { $compiled->($args) };
    if ($@) {
        log_message("ERROR", "Runtime error in tool '$name': $@");
        return { status => "error", data => "Runtime error: $@" };
    }

    # Debug: log result type and content
    log_message("DEBUG", "Sandbox result type=" . (defined($result) ? ref($result) : 'undef') . " content=" . (defined($result) ? $json->encode($result) : 'undef'));

    log_message("INFO", "Executed generated tool: $name");
    return { status => "success", data => $result };
}

# ---------------------------------------------------------------------------
# Built-in tool: weather
# ---------------------------------------------------------------------------
sub tool_weather {
    my ($args) = @_;
    my $city = $args->{city} or die "Missing required parameter: 'city'";

    my $r = _safe_http_get_json("https://wttr.in/$city?format=j1");
    die "HTTP error: $r->{status} - $r->{reason}" unless $r->{success};

    my $d = $r->{data};
    return {
        requested_city => $city,
        city           => ($d->{nearest_area}[0]{areaName}[0]{value} // $city),
        country        => ($d->{nearest_area}[0]{country}[0]{value} // "?"),
        temp_C         => ($d->{current_condition}[0]{temp_C} // "?") + 0,
        feels_like_C   => ($d->{current_condition}[0]{FeelsLikeC} // "?") + 0,
        humidity       => ($d->{current_condition}[0]{humidity} // "?") + 0,
        wind_speed_kmh => ($d->{current_condition}[0]{windspeedKmph} // "?") + 0,
        wind_dir       => ($d->{current_condition}[0]{winddir16Point} // "?"),
        desc           => ($d->{current_condition}[0]{weatherDesc}[0]{value} // "?"),
        obs_time       => ($d->{current_condition}[0]{observation_time} // "?"),
    };
}

# ---------------------------------------------------------------------------
# Built-in tool: exchange_rate
# ---------------------------------------------------------------------------
sub tool_exchange_rate {
    my ($args) = @_;
    my $base   = $args->{base}   // 'USD';
    my $target = $args->{target} // 'RUB';

    my $r = _safe_http_get_json("https://api.exchangerate-api.com/v4/latest/$base");
    die "HTTP error: $r->{status} - $r->{reason}" unless $r->{success};

    my $d = $r->{data};
    my $rate = $d->{rates}{$target};
    die "Target currency '$target' not found." unless defined $rate;

    return {
        base       => $base,
        target     => $target,
        rate       => $rate + 0.0,
        date       => $d->{date},
        source     => "exchangerate-api.com",
    };
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
    elsif ($name eq 'weather') {
        return tool_weather($args);
    }
    elsif ($name eq 'exchange_rate') {
        return tool_exchange_rate($args);
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
        name        => "weather",
        description => "Get current weather for any city. Returns temperature, humidity, wind, and description.",
        inputSchema => {
            type => "object",
            properties => {
                city => {
                    type => "string",
                    description => "City name (supports Cyrillic, e.g. Москва, Саратов)",
                },
            },
            required => ["city"],
        },
    };
    push @tools, {
        name        => "exchange_rate",
        description => "Get exchange rate between two currencies. Default: USD → RUB. Supports any ISO 4217 currency code.",
        inputSchema => {
            type => "object",
            properties => {
                base => {
                    type => "string",
                    description => "Base currency code (default: USD)",
                },
                target => {
                    type => "string",
                    description => "Target currency code (default: RUB)",
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
            my @builtin = qw(tool_generate tool_list tool_export tool_import tool_remove weather exchange_rate);
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